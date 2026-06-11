# Suggests the next training block once the current one ends: a fresh block
# mirroring the most recent one's structure, starting today. Returns nil while a
# block is still running or if the user has never run one.
class NextBlockSuggestion
  RECENT_WINDOW_DAYS = 14

  def initialize(user)
    @user = user
  end

  def call
    return @suggestion if defined?(@suggestion)

    @suggestion = build_suggestion
  end

  # True only for a short window after a block ends, so the dashboard nudge
  # doesn't nag indefinitely.
  def recently_ended?
    return false unless call && last_block

    (@user.local_date - last_block.effective_end).to_i.between?(0, RECENT_WINDOW_DAYS)
  end

  private

  def build_suggestion
    return if active_block?
    return unless last_block

    @user.mesocycles.new(
      name: suggested_name,
      started_on: @user.local_date,
      weeks: last_block.weeks,
      deload_week: last_block.deload_week
    )
  end

  def active_block?
    @user.mesocycles.active_on(@user.local_date).exists?
  end

  def last_block
    @last_block ||= @user.mesocycles.order(started_on: :desc, id: :desc).first
  end

  def suggested_name
    if last_block.name.present? && (match = last_block.name.match(/\A(.*?)(\d+)\s*\z/))
      "#{match[1]}#{match[2].to_i + 1}"
    else
      "Block #{@user.mesocycles.count + 1}"
    end
  end
end
