require "test_helper"

class ErrorReporterTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @reporter = ErrorReporter.new
    @original = ENV["ERROR_REPORT_TO"]
    ENV["ERROR_REPORT_TO"] = "ops@example.com"
  end

  teardown { ENV["ERROR_REPORT_TO"] = @original }

  test "records a failure and tells somebody about it" do
    assert_difference "ErrorReport.count", 1 do
      assert_enqueued_emails 1 do
        @reporter.report(raised, handled: false, severity: :error, source: "application.active_support")
      end
    end

    report = ErrorReport.order(:id).last
    assert_equal "ArgumentError", report.error_class
    assert_equal "error", report.severity
    assert_not_nil report.last_notified_at
  end

  # The second copy of a sentence tells you nothing the first did not, and one
  # error in a recompute sweep fires once per user.
  test "a repeat inside the interval is counted, not re-sent" do
    @reporter.report(raised, handled: false, severity: :error)

    assert_no_difference "ErrorReport.count" do
      assert_no_enqueued_emails do
        @reporter.report(raised, handled: false, severity: :error)
      end
    end

    assert_equal 2, ErrorReport.order(:id).last.occurrences
  end

  test "a failure still firing after the interval is worth saying again" do
    @reporter.report(raised, handled: false, severity: :error)
    ErrorReport.order(:id).last.update!(last_notified_at: ErrorReport::NOTIFY_INTERVAL.ago - 1.minute)

    assert_enqueued_emails 1 do
      @reporter.report(raised, handled: false, severity: :error)
    end
  end

  test "an error the app handled is recorded but nobody is woken" do
    assert_difference "ErrorReport.count", 1 do
      assert_no_enqueued_emails do
        @reporter.report(raised, handled: true, severity: :warning)
      end
    end

    assert ErrorReport.order(:id).last.handled?
  end

  # An alert nobody can receive is not a control, so it is not pretended.
  test "nothing is sent when no address is configured" do
    ENV["ERROR_REPORT_TO"] = nil

    assert_difference "ErrorReport.count", 1 do
      assert_no_enqueued_emails do
        @reporter.report(raised, handled: false, severity: :error)
      end
    end

    assert_nil ErrorReport.order(:id).last.last_notified_at
  end

  test "nothing is sent when mail cannot be delivered" do
    was = ActionMailer::Base.perform_deliveries
    ActionMailer::Base.perform_deliveries = false

    assert_no_enqueued_emails do
      @reporter.report(raised, handled: false, severity: :error)
    end

    assert_nil ErrorReport.order(:id).last.last_notified_at
  ensure
    ActionMailer::Base.perform_deliveries = was
  end

  test "the context carries the job and the user as an id, and nothing else" do
    job = TrainingPlanRecomputeJob.new(users(:one), Date.current)

    @reporter.report(raised, handled: false, severity: :error, context: { job: job })

    context = ErrorReport.order(:id).last.context
    assert_equal "TrainingPlanRecomputeJob", context["job"]
    assert_equal users(:one).id, context["user_id"]
    refute_includes context.to_json, users(:one).email_address
  end

  # The reporter failing must never become the error the caller sees: a broken
  # database would otherwise replace a useful exception with a useless one.
  test "a reporter that cannot record swallows its own failure" do
    failing(ErrorReport, :record!) do
      assert_nothing_raised do
        @reporter.report(raised, handled: false, severity: :error)
      end
    end
  end

  test "a reporter that cannot send the alert still records the failure" do
    failing(ErrorReportsMailer, :alert) do
      assert_difference "ErrorReport.count", 1 do
        assert_nothing_raised { @reporter.report(raised, handled: false, severity: :error) }
      end
    end

    assert_nil ErrorReport.order(:id).last.last_notified_at, "an alert that never went is not a notification"
  end

  private

  # Minitest 6 dropped Object#stub, and this codebase already redefines and
  # restores rather than carrying a mocking gem for it (see push_notifier_test).
  def failing(owner, method_name)
    original = owner.method(method_name)
    owner.define_singleton_method(method_name) { |*, **| raise ActiveRecord::ConnectionNotEstablished }
    yield
  ensure
    owner.define_singleton_method(method_name, original)
  end

  def raised(message = "boom")
    raise ArgumentError, message
  rescue StandardError => e
    e
  end
end
