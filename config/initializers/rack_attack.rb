class Rack::Attack
  EXERCISE_CATALOG_LIMIT = 60
  EXERCISE_CATALOG_PERIOD = 1.minute
  EXERCISE_CATALOG_GLOBAL_LIMIT = 600
  EXERCISE_CATALOG_PATH = %r{\A/api/v1/exercises(?:\.[a-z0-9]+)?/?\z}
  CLIENT_IP = lambda do |request|
    request.get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").first&.strip.presence ||
      ActionDispatch::Request.new(request.env).remote_ip
  end

  LOGIN_PATH = %r{\A/session/?\z}
  LOGIN_LIMIT = 5
  LOGIN_PERIOD = 20.minutes
  WEARABLE_SYNC_PATH = %r{\A/api/v1/wearable_sync/?\z}
  WEARABLE_SYNC_LIMIT = 60
  WEARABLE_SYNC_PERIOD = 1.minute

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
