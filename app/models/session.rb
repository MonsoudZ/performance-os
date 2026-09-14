class Session < ApplicationRecord
  # A session unused for a month is one nobody is coming back to, and the phone
  # it lives on may not be in its owner's hands any more.
  IDLE_TIMEOUT = 30.days

  # Even a session in daily use is eventually made to prove the password again.
  # Idle expiry cannot reach a stolen cookie that is being actively used; only
  # the user revoking it from the list can, and this is the backstop for when
  # nobody looks. Long enough not to interrupt a training block, short enough
  # that credentials are re-proven twice a year.
  ABSOLUTE_LIFETIME = 180.days

  # How stale `last_active_at` is allowed to get before a request writes it.
  # Writing on every request would add a write to every page load to sharpen a
  # thirty-day window by minutes.
  ACTIVITY_PRECISION = 1.hour

  # Matched in order, because a Chrome user agent also says Safari and an Edge
  # one also says Chrome. Deliberately crude: this label only has to help
  # someone answer "is this mine?", and an unrecognized agent is shown as
  # itself rather than guessed at.
  BROWSERS = [
    [ /\bEdg[A-Z]*\//, "Edge" ],
    [ /\bOPR\/|\bOpera\b/, "Opera" ],
    [ /\bChrome\/|\bCriOS\//, "Chrome" ],
    [ /\bFirefox\/|\bFxiOS\//, "Firefox" ],
    [ /\bSafari\//, "Safari" ]
  ].freeze

  PLATFORMS = [
    [ /\biPhone\b/, "iPhone" ],
    [ /\biPad\b/, "iPad" ],
    [ /\bAndroid\b/, "Android" ],
    [ /\bCrOS\b/, "ChromeOS" ],
    [ /\bMac OS X\b|\bMacintosh\b/, "Mac" ],
    [ /\bWindows\b/, "Windows" ],
    [ /\bLinux\b/, "Linux" ]
  ].freeze

  belongs_to :user

  scope :active, -> {
    where(last_active_at: IDLE_TIMEOUT.ago..).where(created_at: ABSOLUTE_LIFETIME.ago..)
  }
  # The exact complement of `active`: not (idle or too old) is not idle and not
  # too old. Kept as its own clause rather than a subquery so the sweep can
  # delete straight through it.
  scope :expired, -> {
    where(last_active_at: ...IDLE_TIMEOUT.ago).or(where(created_at: ...ABSOLUTE_LIFETIME.ago))
  }
  scope :recently_used_first, -> { order(last_active_at: :desc) }

  def expired?
    last_active_at < IDLE_TIMEOUT.ago || created_at < ABSOLUTE_LIFETIME.ago
  end

  # Called on every authenticated request, so it writes only when the stored
  # time has actually gone stale.
  def touch_activity(now: Time.current)
    return if last_active_at > now - ACTIVITY_PRECISION

    update_column(:last_active_at, now)
  end

  # What the user sees in the list of where they are signed in. Never nil: an
  # agent nobody recognizes is worth more to them verbatim than as "Unknown".
  def device_label
    return "Unknown device" if user_agent.blank?

    browser = BROWSERS.find { |pattern, _| user_agent.match?(pattern) }&.last
    platform = PLATFORMS.find { |pattern, _| user_agent.match?(pattern) }&.last

    return user_agent.truncate(60) if browser.nil? && platform.nil?
    return platform if browser.nil?
    return browser if platform.nil?

    "#{browser} on #{platform}"
  end
end
