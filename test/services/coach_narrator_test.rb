require "test_helper"

class CoachNarratorTest < ActiveSupport::TestCase
  MESSAGES_URL = "https://api.anthropic.com/v1/messages".freeze

  setup do
    @user = users(:one)
    @original_key = Rails.application.config.x.anthropic[:api_key]
    Rails.application.config.x.anthropic[:api_key] = "test-key"

    readiness = @user.coaching_decisions.create!(
      decision_type: "daily_readiness", rule_key: "readiness_evaluator.v1", rule_version: "1.0.0",
      inputs: { "metric_date" => @user.local_date.iso8601 },
      output: { "status" => "recover", "headline" => "Recovery is the goal today" },
      confidence: "moderate"
    )
    @decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "recover", "headline" => "Make recovery the training goal", "guidance" => "Back off today." },
      confidence: "moderate"
    )
    @decision.child_links.create!(child_decision: readiness, role: "readiness")
    @narrative = @user.coach_narratives.create!(
      question: "Why am I being told to recover?", coaching_decision: @decision, status: "pending"
    )
  end

  teardown { Rails.application.config.x.anthropic[:api_key] = @original_key }

  test "grounds the prompt on the decision DAG and returns the parsed answer" do
    stub_messages(text: "You're recovering because your readiness came back low.")

    result = CoachNarrator.new(@narrative).call

    assert_equal "You're recovering because your readiness came back low.", result.answer
    assert_equal "claude-opus-4-8", result.model_id
    assert_equal 1200, result.input_tokens
    assert_equal 90, result.output_tokens

    assert_requested :post, MESSAGES_URL do |request|
      body = JSON.parse(request.body)
      system_text = Array(body["system"]).map { |block| block["text"] }.join(" ")
      # The full decision graph — parent output and the linked child — is in the
      # grounded prefix, and the user's question is the message.
      system_text.include?("DECISION DATA") &&
        system_text.include?("Make recovery the training goal") &&
        system_text.include?("Recovery is the goal today") &&
        body.dig("messages", 0, "content") == "Why am I being told to recover?"
    end
  end

  test "places a cache breakpoint on the decision block so repeat questions reuse it" do
    stub_messages(text: "ok")

    CoachNarrator.new(@narrative).call

    assert_requested :post, MESSAGES_URL do |request|
      blocks = JSON.parse(request.body).fetch("system")
      blocks.last["cache_control"] == { "type" => "ephemeral" } &&
        blocks.last["text"].include?("DECISION DATA")
    end
  end

  test "raises NotConfigured when no API key is set" do
    Rails.application.config.x.anthropic[:api_key] = nil

    assert_not CoachNarrator.configured?
    assert_raises(CoachNarrator::NotConfigured) { CoachNarrator.new(@narrative).call }
    assert_not_requested :post, MESSAGES_URL
  end

  private

  def stub_messages(text:)
    body = {
      id: "msg_1", type: "message", role: "assistant", model: "claude-opus-4-8",
      content: [ { type: "text", text: text } ],
      stop_reason: "end_turn", stop_sequence: nil,
      usage: {
        input_tokens: 1200, output_tokens: 90,
        cache_creation_input_tokens: 0, cache_read_input_tokens: 0
      }
    }.to_json
    stub_request(:post, MESSAGES_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" }, body: body
    )
  end
end
