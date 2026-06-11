require "net/http"

# Searches the Open Food Facts database (free, keyless) and maps products to
# per-100g macro rows the catalog can import. Network failures degrade to an
# empty list rather than raising.
class FoodDatabaseSearch
  Result = Data.define(:name, :brand, :serving_grams, :kcal, :protein_g, :carb_g, :fat_g, :code)

  ENDPOINT = "https://world.openfoodfacts.org/cgi/search.pl".freeze
  USER_AGENT = "PerformanceOS/1.0 (training app; contact support@performance-os.app)".freeze
  FIELDS = "code,product_name,brands,nutriments".freeze
  CACHE_TTL = 1.hour

  def initialize(query, limit: 20)
    @query = query.to_s.strip
    @limit = limit
  end

  def call
    return [] if @query.blank?

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      body = fetch
      body ? parse(body) : []
    end
  rescue StandardError => error
    Rails.logger.warn("FoodDatabaseSearch failed for #{@query.inspect}: #{error.class}: #{error.message}")
    []
  end

  private

  def cache_key
    "food_search/#{@limit}/#{@query.downcase}"
  end

  def fetch
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(
      search_terms: @query,
      search_simple: 1,
      action: "process",
      json: 1,
      page_size: @limit,
      fields: FIELDS
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 3
    http.read_timeout = 5

    response = http.get(uri.request_uri, "User-Agent" => USER_AGENT)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def parse(body)
    products = JSON.parse(body)["products"]
    Array(products).filter_map { |product| build_result(product) }
  end

  def build_result(product)
    name = product["product_name"].to_s.strip
    nutriments = product["nutriments"] || {}
    kcal = nutriments["energy-kcal_100g"]
    return if name.blank? || kcal.blank?

    Result.new(
      name: name,
      brand: product["brands"].to_s.split(",").first&.strip.presence,
      serving_grams: 100,
      kcal: kcal.to_f.round(1),
      protein_g: nutriments["proteins_100g"].to_f.round(1),
      carb_g: nutriments["carbohydrates_100g"].to_f.round(1),
      fat_g: nutriments["fat_100g"].to_f.round(1),
      code: product["code"].presence
    )
  end
end
