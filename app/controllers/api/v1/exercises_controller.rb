module Api
  module V1
    class ExercisesController < ActionController::API
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 50

      after_action :set_rate_limit_headers

      def index
        exercises = Exercise.where(user_id: nil)
          .includes(exercise_muscle_contributions: :muscle_group)
          .order(:name)
        exercises = exercises.where(modality: params[:modality]) if params[:modality].present?
        exercises = search(exercises) if params[:query].present?
        total = exercises.count
        returned_exercises = exercises.limit(limit)

        render json: {
          data: returned_exercises.map { |exercise| serialize(exercise) },
          meta: {
            returned: returned_exercises.length,
            total: total,
            limit: limit
          }
        }
      end

      private

      def set_rate_limit_headers
        throttle = request.env.dig("rack.attack.throttle_data", "api/v1/exercises/ip")
        return unless throttle

        response.set_header("X-RateLimit-Limit", throttle.fetch(:limit).to_s)
        response.set_header(
          "X-RateLimit-Remaining",
          [ throttle.fetch(:limit) - throttle.fetch(:count), 0 ].max.to_s
        )
      end

      def search(exercises)
        query = ActiveRecord::Base.sanitize_sql_like(params[:query].strip)
        exercises.where("exercises.name ILIKE ?", "%#{query}%")
      end

      def limit
        params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      end

      def serialize(exercise)
        {
          id: exercise.id,
          name: exercise.name,
          modality: exercise.modality,
          compound: exercise.is_compound,
          default_unit: exercise.default_unit,
          muscles: exercise.exercise_muscle_contributions
            .sort_by { |contribution| [ contribution.role, contribution.muscle_group.name ] }
            .map do |contribution|
              {
                name: contribution.muscle_group.name,
                role: contribution.role
              }
            end
        }
      end
    end
  end
end
