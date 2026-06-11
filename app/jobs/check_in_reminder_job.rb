class CheckInReminderJob < ApplicationJob
  REMINDER_HOUR = 19 # 7pm local

  queue_as :default

  # Run hourly. Each subscribed user is reminded once, at their local reminder
  # hour, only if they haven't completed today's check-in.
  def perform
    User.where(id: PushSubscription.select(:user_id)).find_each do |user|
      next unless user.local_time.hour == REMINDER_HOUR
      next if checked_in_today?(user)

      user.push_subscriptions.find_each do |subscription|
        PushNotifier.deliver(
          subscription,
          title: "Time to check in",
          body: "Log today's recovery to generate your plan.",
          path: "/"
        )
      end
    end
  end

  private

  def checked_in_today?(user)
    user.daily_readiness_inputs.find_by(metric_date: user.local_date)&.checked_in? || false
  end
end
