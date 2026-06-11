require "test_helper"
require "turbo/broadcastable/test_helper"

class CoachNarrativeJobTest < ActiveJob::TestCase
  include Turbo::Broadcastable::TestHelper

  MESSAGES_URL = "https://api.anthropic.com/v1/messages".freeze

  setup do
    @user = users(:one)
    @original_key = Rails.application.config.x.anthropic[:api_key]
    Rails.application.config.x.anthropic[:api_key] = "test-key"

    @decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan", "guidance" => "Go." },
      confidence: "high"
    )
    @narrative = @user.coach_narratives.create!(
      question: "Why push today?", coaching_decision: @decision, status: "pending"
    )
  end

  teardown { Rails.application.config.x.anthropic[:api_key] = @original_key }

  test "fills in the answer and usage and broadcasts a refresh" do
    stub_request(:post, MESSAGES_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        id: "msg_1", type: "message", role: "assistant", model: "claude-opus-4-8",
        content: [ { type: "text", text: "Because your readiness is high." } ],
        stop_reason: "end_turn",
        usage: { input_tokens: 500, output_tokens: 40, cache_creation_input_tokens: 0, cache_read_input_tokens: 320 }
      }.to_json
    )

    assert_turbo_stream_broadcasts [ @user ], count: 1 do
      CoachNarrativeJob.perform_now(@narrative)
    end

    @narrative.reload
    assert @narrative.complete?
    assert_equal "Because your readiness is high.", @narrative.answer
    assert_equal "claude-opus-4-8", @narrative.model_id
    assert_equal 320, @narrative.cache_read_tokens
  end

  test "marks the narrative failed when the API key is missing" do
    Rails.application.config.x.anthropic[:api_key] = nil

    CoachNarrativeJob.perform_now(@narrative)

    assert @narrative.reload.failed?
    assert_not_requested :post, MESSAGES_URL
  end

  test "marks the narrative failed when the API errors" do
    stub_request(:post, MESSAGES_URL).to_return(status: 500, body: { error: { type: "api_error", message: "boom" } }.to_json)

    CoachNarrativeJob.perform_now(@narrative)

    assert @narrative.reload.failed?
  end
end
