class Rack::Attack
  EXERCISE_CATALOG_LIMIT = 60
  EXERCISE_CATALOG_PERIOD = 1.minute
  EXERCISE_CATALOG_GLOBAL_LIMIT = 600
  EXERCISE_CATALOG_PATH = %r{\A/api/v1/exercises(?:\.[a-z0-9]+)?/?\z}
  CLIENT_IP = lambda do |request|
    request.get_header("HTTP_X_FORWARDED_FOR").to_s.split(",").first&.strip.presence ||
      ActionDispatch::Request.new(request.env).remote_ip
  end

  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

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
