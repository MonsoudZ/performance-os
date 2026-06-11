require "test_helper"

class CoachNarrativesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @original_key = Rails.application.config.x.anthropic[:api_key]
    Rails.application.config.x.anthropic[:api_key] = "test-key"

    @decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan", "guidance" => "Go." },
      confidence: "high"
    )
  end

  teardown { Rails.application.config.x.anthropic[:api_key] = @original_key }

  test "creates a pending narrative and enqueues the generator job" do
    assert_difference "CoachNarrative.count", 1 do
      assert_enqueued_with(job: CoachNarrativeJob) do
        post coach_narratives_path, params: { coach_narrative: { question: "Why push today?" } }
      end
    end

    narrative = CoachNarrative.order(:id).last
    assert_equal @user, narrative.user
    assert_equal @decision, narrative.coaching_decision
    assert narrative.pending?
    assert_redirected_to root_path
  end

  test "rejects a blank question" do
    assert_no_difference "CoachNarrative.count" do
      post coach_narratives_path, params: { coach_narrative: { question: "" } }
    end

    assert_redirected_to root_path
    assert flash[:alert].present?
  end

  test "refuses when there is no decision to ground the answer on" do
    @decision.destroy

    assert_no_difference "CoachNarrative.count" do
      post coach_narratives_path, params: { coach_narrative: { question: "Why?" } }
    end

    assert_redirected_to root_path
    assert_match(/check-in/, flash[:alert])
  end

  test "refuses when the AI coach is not configured" do
    Rails.application.config.x.anthropic[:api_key] = nil

    assert_no_difference "CoachNarrative.count" do
      post coach_narratives_path, params: { coach_narrative: { question: "Why?" } }
    end

    assert_redirected_to root_path
  end
end
