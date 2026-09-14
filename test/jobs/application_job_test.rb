require "test_helper"

# The two things every job in this app inherits. Both matter because of what the
# jobs are: recomputes of derived state, queued against Active Record objects.
class ApplicationJobTest < ActiveJob::TestCase
  # Raises a given error a set number of times, then succeeds.
  class FlakyJob < ApplicationJob
    class << self
      attr_accessor :attempts, :error, :error_count

      def reset(error:, error_count:)
        self.attempts = 0
        self.error = error
        self.error_count = error_count
      end
    end

    def perform
      self.class.attempts += 1
      raise self.class.error if self.class.attempts <= self.class.error_count
    end
  end

  setup { @user = users(:one) }

  test "a job queued for a record that no longer exists is finished, not failed" do
    serialized = TrainingPlanRecomputeJob.new(@user, @user.local_date).serialize
    AccountDeletion.new(@user).call

    # Deleting an account takes twenty associations with it while recomputes for
    # them may still be queued. Without this every one of them fails permanently.
    assert_nothing_raised { ActiveJob::Base.execute(serialized) }
  end

  test "discarding says so, because a live account losing records is a different problem" do
    serialized = TrainingPlanRecomputeJob.new(@user, @user.local_date).serialize
    AccountDeletion.new(@user).call

    logged = capture_log { ActiveJob::Base.execute(serialized) }

    assert_match(/TrainingPlanRecomputeJob discarded/, logged)
    assert_match(/no longer exists/, logged)
  end

  test "every job that takes a record inherits the discard" do
    jobs_taking_records = [
      BodyMetricRecomputeJob, CoachNarrativeJob, NutritionRecomputeJob,
      ReadinessRecomputeJob, TrainingPlanRecomputeJob, WearableDayMaterializeJob,
      WeeklyReviewRecomputeJob, WorkoutProgressionRecomputeJob
    ]

    jobs_taking_records.each do |job|
      assert job < ApplicationJob, "#{job} does not inherit the discard or the retry"
    end
  end

  test "transient database contention is retried rather than dropped" do
    FlakyJob.reset(error: ActiveRecord::Deadlocked.new("deadlock detected"), error_count: 2)

    perform_enqueued_jobs { FlakyJob.perform_later }

    assert_equal 3, FlakyJob.attempts, "the third attempt is the one that succeeds"
  end

  test "a database failover is waited out too" do
    FlakyJob.reset(error: ActiveRecord::ConnectionNotEstablished.new("no connection"), error_count: 1)

    perform_enqueued_jobs { FlakyJob.perform_later }

    assert_equal 2, FlakyJob.attempts
  end

  test "contention that never clears eventually surfaces rather than retrying forever" do
    FlakyJob.reset(error: ActiveRecord::Deadlocked.new("deadlock detected"), error_count: 99)

    error = assert_job_raises { perform_enqueued_jobs { FlakyJob.perform_later } }

    assert_instance_of ActiveRecord::Deadlocked, error
    assert_equal ApplicationJob::RETRY_ATTEMPTS, FlakyJob.attempts
  end

  test "a bug is not retried, because five tries only delay finding it" do
    FlakyJob.reset(error: ActiveRecord::StatementInvalid.new("syntax error"), error_count: 99)

    error = assert_job_raises { perform_enqueued_jobs { FlakyJob.perform_later } }

    assert_instance_of ActiveRecord::StatementInvalid, error
    assert_equal 1, FlakyJob.attempts
  end

  private

  # Rails' perform_enqueued_jobs helper wraps whatever escapes a job in
  # Minitest::UnexpectedError, which descends from Minitest::Assertion rather
  # than StandardError — so assert_raises on the real class never matches.
  def assert_job_raises
    yield
    flunk "expected the job to raise once its retries were spent"
  rescue Minitest::UnexpectedError => wrapper
    wrapper.error
  rescue StandardError => error
    error
  end

  def capture_log
    original = Rails.logger
    buffer = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(buffer)
    yield
    buffer.string
  ensure
    Rails.logger = original
  end
end
