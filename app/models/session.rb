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

  # A native client holds one of these instead of a cookie. The prefix makes a
  # leaked token recognisable on sight and greppable in logs; the 43 characters
  # after it are `SecureRandom.urlsafe_base64(32)`, which is 256 bits.
  API_TOKEN_PREFIX = "pos_".freeze
  API_TOKEN_PATTERN = /\Apos_[A-Za-z0-9_-]{43}\z/

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

  # Scoped to `active`, so a token is worth exactly as much as the session that
  # issued it: the same idle and absolute clocks end both, and ending a device
  # from the signed-in list ends its token in the same breath. There is no
  # separate token expiry to drift out of step with those two.
  #
  # SHA-256 rather than bcrypt, unlike a password: there is nothing to guess
  # here — the token is 256 random bits, not something a person chose — and a
  # plain digest makes the lookup one indexed read.
  def self.authenticate_api_token(token)
    return unless token&.match?(API_TOKEN_PATTERN)

    active.find_by(api_token_digest: digest_api_token(token))
  end

  def self.digest_api_token(token)
    Digest::SHA256.hexdigest(token)
  end

  # Returned once and never recoverable: only the digest is stored. Issuing
  # again replaces the old token, so a device that signs in twice invalidates
  # its first token rather than leaving two live.
  def issue_api_token!
    token = "#{API_TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    update!(api_token_digest: self.class.digest_api_token(token))
    token
  end

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
