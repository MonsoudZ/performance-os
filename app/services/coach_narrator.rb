# Explains the app's auditable coaching-decision DAG in plain language.
#
# The whole point of PerformanceOS is that every recommendation is composed from
# immutable, inspectable decisions rather than a black box. This service is the
# fulfilment of that promise: it grounds Claude *only* on the structured
# daily_training decision and its linked children (readiness, progression,
# nutrition, plus the composed conditioning/mesocycle context) and asks it to
# turn that evidence into a human answer to a "why?" question.
#
# Grounding is enforced two ways: the system prompt forbids inventing facts, and
# the model only ever sees the serialized decision data — never the database.
class CoachNarrator
  class NotConfigured < StandardError; end

  MAX_TOKENS = 2_048

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the coach inside PerformanceOS, an evidence-based training and
    nutrition app. Every recommendation the app makes is composed from a graph of
    small, immutable "coaching decisions" — readiness, per-lift progression,
    nutrition, conditioning, and mesocycle context — that combine into one daily
    training decision. The user is asking you to explain that decision.

    You will be given the exact decision data the app used, as JSON, under
    DECISION DATA. Follow these rules without exception:

    - Ground every claim in the provided decision data. Never invent numbers,
      targets, dates, or reasons that are not present in it.
    - If the data does not contain what is needed to answer, say so plainly and
      tell the user which check-in or log would supply it. Do not guess.
    - Explain the chain of cause and effect: which input (readiness status, a
      progression result, a deload week, a nutrition adjustment) drove the
      output the user is seeing. Make the "why" traceable.
    - Write directly to the user in the second person. Be concise and concrete —
      two to four short paragraphs at most, plain text, no markdown headings.
    - You are a training coach, not a doctor. Do not give medical advice; if a
      symptom sounds medical, suggest they consult a professional.
  PROMPT

  def self.configured?
    Rails.application.config.x.anthropic[:api_key].present?
  end

  def initialize(narrative)
    @narrative = narrative
  end

  def call
    raise NotConfigured, "ANTHROPIC_API_KEY is not set" unless self.class.configured?

    message = client.messages.create(
      model: model.to_sym,
      max_tokens: MAX_TOKENS,
      thinking: { type: :adaptive },
      system_: system_blocks,
      messages: [ { role: "user", content: question } ]
    )

    Result.new(
      answer: extract_text(message),
      model_id: message.model.to_s,
      input_tokens: message.usage&.input_tokens,
      output_tokens: message.usage&.output_tokens,
      cache_read_tokens: message.usage&.cache_read_input_tokens
    )
  end

  Result = Struct.new(:answer, :model_id, :input_tokens, :output_tokens, :cache_read_tokens, keyword_init: true)

  private

  attr_reader :narrative

  def question = narrative.question

  # Stable prefix (coaching philosophy + the full decision graph) first, volatile
  # question last. The decision data is identical across every question the user
  # asks about the same plan, so the cache_control breakpoint lets repeated
  # questions reuse it. (Short plans may fall under the model's minimum cacheable
  # prefix and simply won't cache — that's a silent, harmless miss.)
  def system_blocks
    [
      { type: "text", text: SYSTEM_PROMPT },
      {
        type: "text",
        text: "DECISION DATA\n\n#{JSON.pretty_generate(grounding)}",
        cache_control: { type: "ephemeral" }
      }
    ]
  end

  # The decision DAG, flattened to exactly what the model needs: the composed
  # daily_training output and the immutable child decisions it was built from.
  def grounding
    decision = narrative.coaching_decision

    {
      plan_date: decision.inputs["plan_date"],
      confidence: decision.confidence,
      rule: decision.rule_key,
      todays_recommendation: decision.output,
      supporting_decisions: child_decisions(decision)
    }
  end

  def child_decisions(decision)
    decision.child_links.includes(:child_decision).order(:role, :id).map do |link|
      child = link.child_decision
      {
        role: link.role,
        type: child.decision_type,
        rule: child.rule_key,
        confidence: child.confidence,
        inputs: child.inputs,
        output: child.output
      }
    end
  end

  def extract_text(message)
    message.content
      .select { |block| block.type == :text }
      .map(&:text)
      .join("\n")
      .strip
  end

  def client
    @client ||= Anthropic::Client.new(api_key: Rails.application.config.x.anthropic[:api_key])
  end

  def model
    Rails.application.config.x.anthropic[:model]
  end
end
