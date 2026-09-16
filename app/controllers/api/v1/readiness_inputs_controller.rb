module Api
  module V1
    # Correcting a check-in after the day it belongs to.
    #
    # A different question from answering today's, which is why it is a different
    # endpoint: `readiness_check_in` asks "how are you", this one asks "what did
    # you mean to put". So the ratings here are not required — a correction names
    # what it is correcting and leaves the rest alone — but a rating the request
    # names may not be blanked, because un-answering a day still leaves it scored
    # from less than the user actually knows.
    class ReadinessInputsController < BaseController
      include ReadinessAnswers

      DEFAULT_LIMIT = 30
      MAX_LIMIT = 180

      def index
        inputs = current_user.daily_readiness_inputs
          .order(metric_date: :desc)
          .limit(limit)
          .to_a

        render json: { data: inputs.map { |input| serialize(input) } }
      end

      def update
        input = current_user.daily_readiness_inputs.find(params[:id])
        blanked = blanked_ratings
        return unanswerable(blanked, "cannot be cleared once it is answered") if blanked.any?

        input.assign_attributes(readiness_attributes)
        input.source = input.derived_source

        if input.save
          # The same job the web edit runs, so a correction re-scores the day and
          # recomposes the plan exactly as it would from a browser.
          ReadinessRecomputeJob.perform_later(input)
          render json: { data: serialize(input) }
        else
          render json: { error: "Invalid check-in", details: input.errors.full_messages },
            status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      private

      def limit
        params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      end

      def serialize(input)
        ReadinessCheckInSerializer.new(
          date: input.metric_date,
          input: input,
          score: scores[input.metric_date],
          decision: decisions[input.metric_date.iso8601]
        ).as_json
      end

      def scores
        @scores ||= current_user.readiness_scores.index_by(&:score_date)
      end

      # Loaded for the whole page in one query rather than one per day, and
      # scoped to active_evidence like every lookup that answers "what does the
      # engine say": a withdrawn decision is part of the record but is never the
      # answer. Latest first, so the first one seen for a date is the one kept.
      def decisions
        @decisions ||= current_user.coaching_decisions
          .active_evidence
          .of_type("daily_readiness")
          .latest_first
          .each_with_object({}) do |decision, by_date|
            date = decision.inputs["metric_date"]
            by_date[date] ||= decision
          end
      end
    end
  end
end
