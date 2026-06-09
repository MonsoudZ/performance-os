module Api
  module V1
    class ExercisesController < ActionController::API
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 50

      def index
        exercises = Exercise.where(user_id: nil)
          .includes(exercise_muscle_contributions: :muscle_group)
          .order(:name)
        exercises = exercises.where(modality: params[:modality]) if params[:modality].present?
        exercises = search(exercises) if params[:query].present?
        exercises = exercises.limit(limit)

        render json: {
          data: exercises.map { |exercise| serialize(exercise) },
          meta: { count: exercises.length }
        }
      end

      private

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
