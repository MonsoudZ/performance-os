# How many questions an account may ask the coach in a day, and whether it has
# any left.
#
# Every other guard around the coach limits how many *accounts* one person can
# hold — the registration throttle, email confirmation, the per-mailbox cap.
# None of them limits what a single account can spend, and asking the coach is
# the one action in this app that costs real money per press. This is that
# limit.
#
# It is a product limit rather than an attack response, so it is enforced here
# and rendered as a sentence, not returned as a 429 from Rack::Attack. A user
# who has asked their questions should be told when they get more, not handed a
# status code.
class CoachBudget
  # Understanding one day's plan does not take twenty questions; scripting a bill
  # takes far more than twenty. With the per-mailbox cap this puts a ceiling of
  # sixty a day on one inbox.
  DAILY_LIMIT = 20

  # When to start saying how many are left. Showing a counter from the first
  # question would nag; showing nothing until the wall would surprise.
  LOW_WATER = 5

  def initialize(user, on: nil)
    @user = user
    @date = on || user.local_date
  end

  def limit = DAILY_LIMIT

  # Not memoized: `claim` counts again inside the lock, and a stale count there
  # is the whole bug it exists to prevent.
  def spent = counted.count

  def remaining = [ limit - spent, 0 ].max

  def exhausted? = remaining.zero?

  def running_low? = !exhausted? && remaining <= LOW_WATER

  # The user's own next midnight, like every other day boundary here. A budget
  # that reset at UTC midnight would refill mid-afternoon for a user in Denver.
  # Built from the next day's range rather than the end of this one, so it is
  # the moment the budget refills rather than the last instant before it.
  def resets_at = user.local_day_range(date + 1).begin

  # Creates the narrative only if the day has room for it. The count and the
  # insert happen under a lock on the user's own row, so two questions asked at
  # the same moment cannot both be sold the last slot. The lock is contended
  # only by the same user, and only for the length of one insert.
  def claim
    user.with_lock do
      exhausted? ? nil : yield
    end
  end

  private

  attr_reader :user, :date

  # A question the coach could not answer is not one the user got, and a failure
  # means the call raised rather than billed — so it gives the slot back. A
  # pending one still counts: the call is already in flight, and refunding it
  # would make a burst of unanswered questions free.
  def counted
    user.coach_narratives
      .where(created_at: user.local_day_range(date))
      .where.not(status: "failed")
  end
end
