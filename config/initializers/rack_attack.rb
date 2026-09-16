class Rack::Attack
  EXERCISE_CATALOG_LIMIT = 60
  EXERCISE_CATALOG_PERIOD = 1.minute
  EXERCISE_CATALOG_GLOBAL_LIMIT = 600
  EXERCISE_CATALOG_PATH = %r{\A/api/v1/exercises(?:\.[a-z0-9]+)?/?\z}
  CLIENT_IP = lambda do |request|
    request.get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").first&.strip.presence ||
      ActionDispatch::Request.new(request.env).remote_ip
  end

  # The native sign-in is the same credential-stuffing target as the web form
  # and needs its own throttle: the web one keys on a different path and would
  # never see these.
  API_LOGIN_PATH = %r{\A/api/v1/session/?\z}

  LOGIN_PATH = %r{\A/session/?\z}
  LOGIN_LIMIT = 5
  LOGIN_PERIOD = 20.minutes
  WEARABLE_SYNC_PATH = %r{\A/api/v1/wearable_sync/?\z}
  WEARABLE_SYNC_LIMIT = 60
  WEARABLE_SYNC_PERIOD = 1.minute
  FOOD_SEARCH_PATH = %r{\A/foods/search/?\z}
  FOOD_SEARCH_LIMIT = 20
  FOOD_SEARCH_PERIOD = 1.minute

  # The native food search spends the same outbound request as the web one and
  # needs its own throttle for the same reason the native sign-in does: the web
  # rule keys on a path this never matches.
  API_FOOD_SEARCH_PATH = %r{\A/api/v1/foods/search(?:\.[a-z0-9]+)?/?\z}
  REGISTRATION_PATH = %r{\A/registration/?\z}
  REGISTRATION_LIMIT = 10
  REGISTRATION_PERIOD = 1.hour

  # In production the counters live in the shared Solid Cache so every Puma
  # worker (and any future dyno) enforces one global limit. In dev/test a
  # per-process memory store keeps throttle counting deterministic.
  Rack::Attack.cache.store =
    if Rails.env.production?
      Rails.cache
    else
      ActiveSupport::Cache::MemoryStore.new
    end

  throttle(
    "api/v1/session/ip",
    limit: LOGIN_LIMIT,
    period: LOGIN_PERIOD
  ) do |request|
    CLIENT_IP.call(request) if request.post? && request.path.match?(API_LOGIN_PATH)
  end

  throttle(
    "api/v1/exercises/ip",
    limit: EXERCISE_CATALOG_LIMIT,
    period: EXERCISE_CATALOG_PERIOD
  ) do |request|
    CLIENT_IP.call(request) if request.get? && request.path.match?(EXERCISE_CATALOG_PATH)
  end

  throttle(
    "api/v1/exercises/global",
    limit: EXERCISE_CATALOG_GLOBAL_LIMIT,
    period: EXERCISE_CATALOG_PERIOD
  ) do |request|
    "exercise-catalog" if request.get? && request.path.match?(EXERCISE_CATALOG_PATH)
  end

  # Throttle login attempts per submitted account so credential-stuffing can't
  # spread across IPs to evade the per-IP limit in SessionsController.
  throttle(
    "login/email",
    limit: LOGIN_LIMIT,
    period: LOGIN_PERIOD
  ) do |request|
    if request.post? && request.path.match?(LOGIN_PATH)
      request.params["email_address"].to_s.downcase.strip.presence
    end
  end

  # Throttle the wearable sync endpoint per device (the id prefix of the bearer
  # token, never the secret). Batches accept up to 1,000 samples each, so this
  # caps how hard one compromised device token can hammer the ingestion path.
  throttle(
    "api/v1/wearable_sync/device",
    limit: WEARABLE_SYNC_LIMIT,
    period: WEARABLE_SYNC_PERIOD
  ) do |request|
    if request.post? && request.path.match?(WEARABLE_SYNC_PATH)
      request.get_header("HTTP_AUTHORIZATION").to_s.delete_prefix("Bearer ").split(".", 2).first.presence
    end
  end

  # Each food search triggers an outbound Open Food Facts request, so cap how
  # fast one signed-in session (or IP, when there's no session) can issue them.
  throttle(
    "foods/search",
    limit: FOOD_SEARCH_LIMIT,
    period: FOOD_SEARCH_PERIOD
  ) do |request|
    if request.get? && request.path.match?(FOOD_SEARCH_PATH)
      request.cookies["session_id"].presence || CLIENT_IP.call(request)
    end
  end

  # Keyed on the token's digest, not the token. The digest is what the database
  # already stores and is worthless to anyone who learns it, so counting against
  # it puts no credential into the throttle store — and it means the limit
  # follows the device rather than the network it is on, so a gym's shared wifi
  # does not make one phone's typing count against another's.
  throttle(
    "api/v1/foods/search/device",
    limit: FOOD_SEARCH_LIMIT,
    period: FOOD_SEARCH_PERIOD
  ) do |request|
    if request.get? && request.path.match?(API_FOOD_SEARCH_PATH)
      token = request.get_header("HTTP_AUTHORIZATION").to_s.delete_prefix("Bearer ")
      token.present? ? Session.digest_api_token(token) : CLIENT_IP.call(request)
    end
  end

  # Signing up is rare for a person and trivial to script, and unlike logging in
  # there is no second axis to key on — every account is a different address by
  # definition. So the cap is per client IP and generous enough that a household
  # or an office behind one address never notices: ten new accounts in an hour is
  # far past anything real and far under what filling a table takes.
  #
  # This does not stop a caller with many addresses. Three other things do, and
  # each covers what the others cannot: confirmation proves the address exists,
  # User::ACCOUNTS_PER_MAILBOX caps how many accounts one inbox can hold, and
  # CoachBudget caps what any single account can spend once it is in.
  throttle(
    "registration/ip",
    limit: REGISTRATION_LIMIT,
    period: REGISTRATION_PERIOD
  ) do |request|
    CLIENT_IP.call(request) if request.post? && request.path.match?(REGISTRATION_PATH)
  end

  self.throttled_response_retry_after_header = true
  self.throttled_responder = lambda do |request|
    match_data = request.env.fetch("rack.attack.match_data")
    retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_i.to_s,
        "X-RateLimit-Limit" => match_data[:limit].to_s,
        "X-RateLimit-Remaining" => "0"
      },
      [ { error: "Rate limit exceeded" }.to_json ]
    ]
  end
end
