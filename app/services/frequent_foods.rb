# The foods worth offering as one tap, and the portion to offer them at.
#
# This was the six most recently logged distinct foods, which is a different
# thing from the six you actually eat: log a few unusual meals and your staples
# fall off the list exactly when you want them. Ranking by how often a food
# shows up keeps the staples pinned, and bounding the window means something you
# have stopped eating stops being offered.
class FrequentFoods
  WINDOW_DAYS = 14
  LIMIT = 6

  # A food, the portion the user last logged it at, and the macros that follow
  # from that portion. The portion is the memory worth keeping — the whole point
  # is not retyping "80" every morning.
  Suggestion = Data.define(:food, :quantity_grams, :kcal, :protein_g, :times_logged)

  def initialize(user, now: Time.current, limit: LIMIT)
    @user = user
    @now = now
    @limit = limit
  end

  def call
    ranked_entries.map do |entries|
      latest = entries.max_by(&:logged_at)
      Suggestion.new(
        food: latest.food,
        quantity_grams: latest.quantity_grams,
        kcal: latest.kcal,
        protein_g: latest.protein_g,
        times_logged: entries.size
      )
    end
  end

  private

  attr_reader :user, :now, :limit

  # Most often first, and the more recent of two equals first — so a tie between
  # a daily staple and something eaten as much last week resolves towards the
  # one still in the rotation.
  def ranked_entries
    user.food_log_entries
      .where.not(food_id: nil)
      .where(logged_at: (now - WINDOW_DAYS.days)..now)
      .includes(:food)
      .group_by(&:food_id)
      .values
      .sort_by { |entries| [ -entries.size, -entries.max_by(&:logged_at).logged_at.to_i ] }
      .first(limit)
  end
end
