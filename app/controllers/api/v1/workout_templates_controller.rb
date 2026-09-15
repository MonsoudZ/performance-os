module Api
  module V1
    class WorkoutTemplatesController < BaseController
      def index
        templates = current_user.workout_templates
          .includes(workout_template_exercises: :exercise)
          .order(:name)

        render json: { data: templates.map { |template| serialize(template) } }
      end

      def show
        template = current_user.workout_templates
          .includes(workout_template_exercises: :exercise)
          .find(params[:id])

        render json: { data: serialize(template) }
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      private

      def serialize(template)
        WorkoutTemplateSerializer.new(template, targets: targets).as_json
      end

      def targets
        @targets ||= ResolvedTrainingTargets.new(current_user)
      end
    end
  end
end
