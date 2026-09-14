require "test_helper"

class ErrorReportsMailerTest < ActionMailer::TestCase
  setup do
    @original = ENV["ERROR_REPORT_TO"]
    ENV["ERROR_REPORT_TO"] = "ops@example.com"
  end

  teardown { ENV["ERROR_REPORT_TO"] = @original }

  test "the alert says what broke, where, and how often" do
    mail = ErrorReportsMailer.alert(report(occurrences: 4))

    assert_equal [ "ops@example.com" ], mail.to
    assert_match(/4×/, mail.subject)
    assert_match(/ActiveRecord::Deadlocked/, mail.subject)

    [ mail.html_part, mail.text_part ].each do |part|
      body = part.body.to_s
      assert_match(/ActiveRecord::Deadlocked/, body)
      assert_match(/could not serialize access/, body)
      assert_match(/4 times/, body)
      assert_match(/TrainingPlanRecomputeJob/, body)
      assert_match(/app\/jobs\/training_plan_recompute_job\.rb/, body)
    end
  end

  # A first sighting should not read as if it had been happening for a while.
  test "a first sighting carries no count in the subject" do
    assert_no_match(/×/, ErrorReportsMailer.alert(report).subject)
  end

  private

  def report(occurrences: 1)
    ErrorReport.new(
      fingerprint: "abc123",
      error_class: "ActiveRecord::Deadlocked",
      message: "PG::TRSerializationFailure: ERROR: could not serialize access due to concurrent update",
      backtrace: "app/jobs/training_plan_recompute_job.rb:9:in `perform'",
      source: "application.active_support",
      severity: "error",
      handled: false,
      context: { "job" => "TrainingPlanRecomputeJob", "attempt" => 5, "user_id" => 12 },
      occurrences: occurrences,
      first_seen_at: 3.hours.ago,
      last_seen_at: Time.current
    )
  end
end
