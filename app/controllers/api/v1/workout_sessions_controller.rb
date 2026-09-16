module Api
  module V1
    # Logging a workout from the phone.
    #
    # Creating one goes through the same recompute pipeline the web logger uses,
    # so a session logged on the phone writes progression decisions exactly like
    # one logged in a browser. It does not evaluate inline — the job does — so
    # the client gets its 201 back without waiting for the engine.
    class WorkoutSessionsController < BaseController
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
        session.attach_template(requested_template)

        if session.save
          WorkoutProgressionRecomputeJob.perform_later(session)
          render json: { data: WorkoutSessionSerializer.new(session).as_json }, status: :created
        else
          render json: { error: "Invalid workout", details: session.errors.full_messages },
            status: :unprocessable_entity
        end
      end

      private

      # Looked up through the user's own templates rather than assigned from the
      # id, so a foreign one comes back nil the way it does on the web. The model
      # refuses it as well: this is the path that should never produce one, and
      # that is the backstop for every other path.
      def requested_template
        current_user.workout_templates.find_by(id: params.dig(:workout_session, :workout_template_id))
      end

      # Weights arrive in kilograms and are stored as they arrive. Nothing is
      # converted here, and that is the rule for this whole boundary: a native
      # request is a record being transported, so the client converts at its own
      # display edge using the `unit_system` on the profile.
      #
      # `MeasurementParams#to_canonical_units` is the web forms' converter and
      # belongs to them. Calling it here read an imperial user's kilograms as
      # pounds — a round trip through the phone turned 100 kg into 45.36 — and
      # it did so only for a payload whose nested sets arrived as a hash keyed by
      # index, because its nested branch tests `respond_to?(:each_value)` and an
      # array does not answer to that. So the same logical payload stored two
      # different weights depending on how the client spelled it, and the array
      # form a JSON client reaches for first was the one that looked correct.
      def workout_session_params
        params.require(:workout_session).permit(
          :performed_at,
          :session_rpe,
          :notes,
          set_entries_attributes: [ :exercise_id, :set_index, :weight_kg, :reps, :rir, :is_warmup ]
        )
      end
    end
  end
end
