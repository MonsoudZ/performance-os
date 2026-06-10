class Rack::Attack
  EXERCISE_CATALOG_LIMIT = 60
  EXERCISE_CATALOG_PERIOD = 1.minute
  EXERCISE_CATALOG_PATH = %r{\A/api/v1/exercises(?:\.[a-z0-9]+)?/?\z}

  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  throttle(
    "api/v1/exercises/ip",
    limit: EXERCISE_CATALOG_LIMIT,
    period: EXERCISE_CATALOG_PERIOD
  ) do |request|
    request.ip if request.get? && request.path.match?(EXERCISE_CATALOG_PATH)
  end

  self.throttled_response_retry_after_header = true
  self.throttled_responder = lambda do |request|
    match_data = request.env.fetch("rack.attack.match_data")
    retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_i.to_s
      },
      [ { error: "Rate limit exceeded" }.to_json ]
    ]
  end
end
