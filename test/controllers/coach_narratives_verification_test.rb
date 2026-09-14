require "test_helper"

# The AI coach is the one surface where an unconfirmed address costs real money
# rather than a table row, so it is the one thing confirmation gates.
class CoachNarrativesVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    Rails.application.config.x.anthropic[:api_key] = "test-key"
  end

  teardown { Rails.application.config.x.anthropic[:api_key] = nil }

  test "an unconfirmed account cannot spend money on the coach" do
    @user.update!(verified_at: nil)

    assert_no_difference "CoachNarrative.count" do
      post coach_narratives_path, params: { coach_narrative: { question: "Why this plan?" } }
    end

    assert_match(/Confirm your email address/, flash[:alert])
  end

  test "a confirmed account can" do
    create_todays_plan

    assert_difference "CoachNarrative.count", 1 do
      post coach_narratives_path, params: { coach_narrative: { question: "Why this plan?" } }
    end
  end

  test "nobody is gated when confirmation cannot be delivered in the first place" do
    @user.update!(verified_at: nil)
    create_todays_plan
    ActionMailer::Base.perform_deliveries = false

    # Enforcing a confirmation nobody can complete is an outage, not security.
    assert_difference "CoachNarrative.count", 1 do
      post coach_narratives_path, params: { coach_narrative: { question: "Why this plan?" } }
    end
  ensure
    ActionMailer::Base.perform_deliveries = true
  end

  test "the banner names what is held back, and goes once confirmed" do
    @user.update!(verified_at: nil)

    get root_path
    assert_select ".flash--alert", text: /Confirm one@example\.com/
    assert_select "form[action=?]", email_verifications_path

    @user.verify!
    get root_path
    assert_select "form[action=?]", email_verifications_path, count: 0
  end

  private

  def create_todays_plan
    @user.coaching_decisions.create!(
      decision_type: "daily_training",
      rule_key: "daily_training.v1",
      rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "headline" => "Plan", "guidance" => "Guidance.", "lifts" => [] },
      citations: [],
      confidence: "high"
    )
  end
end
