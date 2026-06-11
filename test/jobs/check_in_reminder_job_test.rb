require "test_helper"

class CheckInReminderJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "UTC")
    @user.push_subscriptions.create!(endpoint: "https://push.example/abc", p256dh_key: "p", auth_key: "a")
    @reminder_time = Time.utc(2026, 6, 11, CheckInReminderJob::REMINDER_HOUR, 0)
  end

  test "reminds a subscribed user at their local reminder hour when not checked in" do
    delivered = run_at(@reminder_time)

    assert_equal [ @user.push_subscriptions.first ], delivered
  end

  test "does not remind outside the reminder hour" do
    assert_empty run_at(Time.utc(2026, 6, 11, 12, 0))
  end

  test "does not remind a user who already completed today's check-in" do
    @user.daily_readiness_inputs.create!(
      metric_date: Date.new(2026, 6, 11),
      sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3, source: "manual"
    )

    assert_empty run_at(@reminder_time)
  end

  test "ignores users without a subscription" do
    @user.push_subscriptions.destroy_all

    assert_empty run_at(@reminder_time)
  end

  private

  def run_at(time)
    delivered = []
    original = PushNotifier.method(:deliver)
    PushNotifier.define_singleton_method(:deliver) { |subscription, **| delivered << subscription }
    travel_to(time) { CheckInReminderJob.perform_now }
    delivered
  ensure
    PushNotifier.define_singleton_method(:deliver, original)
  end
end
