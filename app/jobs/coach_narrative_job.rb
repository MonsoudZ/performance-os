class CoachNarrativeJob < ApplicationJob
  queue_as :default

  # Generating the narrative is a network call to Claude, so it runs off the web
  # thread. When it lands, the dashboard morph-refreshes and the pending bubble
  # is replaced with the answer — same eventual-consistency UX as the daily plan.
  def perform(narrative)
    return if narrative.coaching_decision.blank?

    result = CoachNarrator.new(narrative).call

    narrative.update!(
      status: "complete",
      answer: result.answer,
      model_id: result.model_id,
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      cache_read_tokens: result.cache_read_tokens
    )
  rescue CoachNarrator::NotConfigured, Anthropic::Errors::Error => e
    Rails.logger.warn("CoachNarrativeJob failed for ##{narrative.id}: #{e.class} #{e.message}")
    narrative.update!(status: "failed")
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(narrative.user)
  end
end
