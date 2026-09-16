module Api
  module V1
    # The daily check-in.
    #
    # `show` reports what is answered and what is not; it never fills anything
    # in. `create` insists on all four subjective ratings, which is what the web
    # form's `required` attributes enforce and what keeps the rule honest from
    # here: without it a native client could post an empty check-in and have the
    # day scored from nothing, which is the same failure as materialising a
    # check-in from a day that only synced steps.
    class ReadinessCheckInsController < BaseController
      include ReadinessAnswers

      REQUIRED_RATINGS = DailyReadinessInput::SUBJECTIVE_FIELDS

      before_action :set_requested_date, only: :show

      def show
        input = current_user.daily_readiness_inputs.find_by(metric_date: date)

        render json: {
          data: ReadinessCheckInSerializer.new(
            date: date,
            input: input,
            score: current_user.readiness_scores.find_by(score_date: date),
            decision: decision
          ).as_json
        }
      end

      # Today only, like the web. Correcting an earlier day is a different
      # action with a different question behind it — "what did I mean to put" —
      # and it lives at /readiness_inputs.
      def create
        missing = REQUIRED_RATINGS.reject { |field| readiness_params[field].present? }
        return unanswerable(missing, "is required") if missing.any?

        input = save_today_check_in

        if input.persisted? && input.errors.empty?
          ReadinessRecomputeJob.perform_later(input)
          render json: { data: serialize(input) }, status: :created
        else
          render json: { error: "Invalid check-in", details: input.errors.full_messages },
            status: :unprocessable_entity
        end
      end

      private

      def decision
        current_user.coaching_decisions
          .active_evidence
          .of_type("daily_readiness")
          .for_input("metric_date", date.iso8601)
          .latest_first
          .first
      end

      # A double-submit can race two find_or_initialize_by inserts against the
      # unique (user_id, metric_date) index. Retry once so the loser finds the
      # now existing row and updates it instead of raising an unhandled 500.
      def save_today_check_in
        attempts = 0
        begin
          input = current_user.daily_readiness_inputs.find_or_initialize_by(metric_date: current_user.local_date)
          input.assign_attributes(readiness_attributes)
          input.source = input.derived_source
          input.save
          input
        rescue ActiveRecord::RecordNotUnique
          raise if (attempts += 1) > 1

          retry
        end
      end

      def serialize(input)
        ReadinessCheckInSerializer.new(
          date: input.metric_date,
          input: input,
          # The score and the decision are the recompute job's to write, and it
          # has only just been queued. The client reads them back from `show`
          # once the plan is ready rather than being handed yesterday's.
          score: nil,
          decision: nil
        ).as_json
      end
    end
  end
end
