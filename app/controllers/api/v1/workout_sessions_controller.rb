module Api
  module V1
    # Logging a workout from the phone.
    #
    # Creating one goes through the same recompute pipeline the web logger uses,
    # so a session logged on the phone writes progression decisions exactly like
    # one logged in a browser. It does not evaluate inline — the job does — so
    # the client gets its 201 back without waiting for the engine.
    class WorkoutSessionsController < BaseController
      include MeasurementParams
      include TrainingRecomputable

      PER_PAGE = 25

      def index
        sessions = current_user.workout_sessions
          .includes(set_entries: :exercise)
          .order(performed_at: :desc)
          .limit(PER_PAGE)

        render json: { data: sessions.map { |session| WorkoutSessionSerializer.new(session).as_json } }
      end

      def show
        session = current_user.workout_sessions.includes(set_entries: :exercise).find(params[:id])

        render json: { data: WorkoutSessionSerializer.new(session).as_json }
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      def create
        session = current_user.workout_sessions.new(workout_session_params)

        if session.save
          WorkoutProgressionRecomputeJob.perform_later(session)
          render json: { data: WorkoutSessionSerializer.new(session).as_json }, status: :created
        else
          render json: { error: "Invalid workout", details: session.errors.full_messages },
            status: :unprocessable_entity
        end
      end

      private

      # Weights arrive in kilograms, like everything else on this boundary, but
      # they go through the same conversion helper the web forms use so there is
      # exactly one place that decides what a measurement field is.
      def workout_session_params
        to_canonical_units(
          params.require(:workout_session).permit(
            :performed_at,
            :session_rpe,
            :notes,
            :workout_template_id,
            set_entries_attributes: [ :exercise_id, :set_index, :weight_kg, :reps, :rir, :is_warmup ]
          ),
          weights: [ :weight_kg ],
          nested: :set_entries_attributes
        )
      end
    end
  end
end
