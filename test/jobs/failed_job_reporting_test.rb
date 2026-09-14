require "test_helper"

# The failure this whole thing exists for: a job exhausts ApplicationJob's
# retries, lands in solid_queue_failed_executions, and the user's plan silently
# stops updating. Rails routes that to Rails.error; these assert the subscriber
# is actually wired to it rather than that the pieces work in isolation.
class FailedJobReportingTest < ActiveJob::TestCase
  class AlwaysDeadlocks < ApplicationJob
    def perform(_user) = raise(ActiveRecord::Deadlocked, "contention")
  end

  class AlwaysBroken < ApplicationJob
    def perform(_user) = raise(ArgumentError, "a bug, not contention")
  end

  setup do
    @user = users(:one)
    @original = ENV["ERROR_REPORT_TO"]
    ENV["ERROR_REPORT_TO"] = "ops@example.com"
    ErrorReport.delete_all
  end

  teardown { ENV["ERROR_REPORT_TO"] = @original }

  test "a job that exhausts its retries is reported once, not once per attempt" do
    assert_difference "ErrorReport.count", 1 do
      swallow { perform_enqueued_jobs { AlwaysDeadlocks.perform_later(@user) } }
    end

    report = ErrorReport.order(:id).last
    assert_equal "ActiveRecord::Deadlocked", report.error_class
    assert_equal 1, report.occurrences, "the retries in between are not four more failures"
    assert_equal ApplicationJob::RETRY_ATTEMPTS, report.context["attempt"]
    assert_equal @user.id, report.context["user_id"]
    assert_equal AlwaysDeadlocks.name, report.context["job"]
  end

  test "a job that fails for a reason nothing retries is reported immediately" do
    assert_difference "ErrorReport.count", 1 do
      swallow { perform_enqueued_jobs { AlwaysBroken.perform_later(@user) } }
    end

    report = ErrorReport.order(:id).last
    assert_equal "ArgumentError", report.error_class
    assert_equal 1, report.context["attempt"]
  end

  # Deleting an account leaves recomputes queued for records that are gone. That
  # is expected and already logged; turning it into an alert would mean an email
  # every time somebody closes their account.
  test "a job discarded because its record is gone is not reported" do
    assert_no_difference "ErrorReport.count" do
      swallow do
        perform_enqueued_jobs do
          TrainingPlanRecomputeJob.perform_later(@user, Date.current)
          AccountDeletion.new(@user).call
        end
      end
    end
  end

  private

  # perform_enqueued_jobs re-raises whatever the job raised, wrapped; the point
  # of these tests is what was recorded on the way past.
  def swallow
    yield
  rescue Exception # rubocop:disable Lint/SuppressedException, Lint/RescueException
  end
end
