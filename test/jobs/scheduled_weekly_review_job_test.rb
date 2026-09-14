require "test_helper"

class ScheduledWeeklyReviewJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    users(:two).update!(time_zone: "America/Denver")
    # Every other fixture user would otherwise sit at the same local hour and
    # make "enqueued for exactly this user" ambiguous.
    User.where.not(id: @user.id).find_each { |other| other.weight_trends.delete_all }
  end

  test "runs a user's review at their own local hour" do
    give_evidence(@user)

    assert_enqueued_with(job: WeeklyReviewRecomputeJob, args: [ @user ]) do
      at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }
    end
  end

  test "does nothing at any other hour" do
    give_evidence(@user)

    assert_no_enqueued_jobs only: WeeklyReviewRecomputeJob do
      at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR + 3) { ScheduledWeeklyReviewJob.perform_now }
    end
  end

  # The window is the user's own week, so two people on the same server get
  # their review at their own Monday morning, not at one shared instant.
  test "the local hour is each user's own" do
    other = users(:two)
    other.update!(time_zone: "Europe/Berlin")
    give_evidence(@user)
    give_evidence(other)

    at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }

    enqueued = enqueued_jobs.select { |job| job["job_class"] == "WeeklyReviewRecomputeJob" }
    assert_equal 1, enqueued.size, "only the user whose local hour it is should be reviewed"
  end

  # Asserted about this user rather than the whole queue, so it fails for the
  # reason it names instead of because some other account was picked up.
  test "does not review a week that has already been reviewed" do
    give_evidence(@user)
    already_reviewed(@user)

    at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }

    assert_empty reviews_enqueued_for(@user)
  end

  # A review of a week the account recorded nothing in would put "keep
  # collecting evidence" on the record every week forever.
  test "does not review a week the account recorded nothing in" do
    assert_no_enqueued_jobs only: WeeklyReviewRecomputeJob do
      at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }
    end
  end

  test "partial evidence is still reviewed, because being told what is missing is the point" do
    @user.weight_trends.create!(trend_date: last_week.first, raw_kg: 80, ewma_kg: 80)

    assert_enqueued_with(job: WeeklyReviewRecomputeJob, args: [ @user ]) do
      at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }
    end
  end

  # Checked every day rather than only on the day the week turns, so a review
  # the worker missed is picked up rather than skipped.
  test "a missed review is caught up later in the week" do
    give_evidence(@user)

    assert_enqueued_with(job: WeeklyReviewRecomputeJob, args: [ @user ]) do
      travel_to local_review_time + 3.days do
        ScheduledWeeklyReviewJob.perform_now
      end
    end
  end

  test "logged intake counts as evidence even with no weigh-ins" do
    @user.coaching_decisions.create!(
      decision_type: "daily_nutrition", rule_key: "nutrition.v1", rule_version: "1.0.0",
      inputs: { "nutrition_date" => last_week.last.iso8601 },
      output: { "status" => "on_target" }, confidence: "moderate"
    )

    assert_enqueued_with(job: WeeklyReviewRecomputeJob, args: [ @user ]) do
      at_local_hour(ScheduledWeeklyReviewJob::REVIEW_HOUR) { ScheduledWeeklyReviewJob.perform_now }
    end
  end

  private

  def reviews_enqueued_for(user)
    enqueued_jobs.select do |job|
      job["job_class"] == "WeeklyReviewRecomputeJob" &&
        job["arguments"].first&.dig("_aj_globalid").to_s.end_with?("/User/#{user.id}")
    end
  end

  def zone = ActiveSupport::TimeZone[@user.time_zone]

  # The most recent moment that is both the user's review hour and a day on
  # which last week's review is due.
  def local_review_time
    monday = zone.today.beginning_of_week
    zone.local(monday.year, monday.month, monday.day, ScheduledWeeklyReviewJob::REVIEW_HOUR)
  end

  def at_local_hour(hour, &block)
    monday = zone.today.beginning_of_week
    travel_to zone.local(monday.year, monday.month, monday.day, hour), &block
  end

  def last_week
    monday = zone.today.beginning_of_week
    period_end = monday - 1.day
    (period_end - (WeeklyEvidenceReview::REVIEW_DAYS - 1).days)..period_end
  end

  def give_evidence(user)
    last_week.each do |date|
      user.weight_trends.create!(trend_date: date, raw_kg: 80, ewma_kg: 80)
    end
  end

  def already_reviewed(user)
    user.coaching_decisions.create!(
      decision_type: "weekly_review",
      rule_key: WeeklyEvidenceReview::RULE_KEY,
      rule_version: "1.0.0",
      inputs: { "period_end" => last_week.last.iso8601 },
      output: { "status" => "continue" },
      confidence: "moderate"
    )
  end
end
