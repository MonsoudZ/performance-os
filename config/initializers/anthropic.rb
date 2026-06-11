# Anthropic API access for the AI coach narrative. Set ANTHROPIC_API_KEY in the
# environment. Without it the narrative service stays dormant and the dashboard
# hides the "Ask your coach" panel, so the rest of the app runs unchanged.
Rails.application.config.x.anthropic = {
  api_key: ENV["ANTHROPIC_API_KEY"],
  # Opus 4.8 — the most capable model; this is the one feature where reasoning
  # quality over the structured decision data is the whole point.
  model: ENV.fetch("ANTHROPIC_MODEL", "claude-opus-4-8")
}
