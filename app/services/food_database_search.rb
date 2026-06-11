require "net/http"

# Searches the Open Food Facts database (free, keyless) and maps products to
# per-100g macro rows the catalog can import. A digit-only query is treated as a
# barcode and looked up directly. Network failures degrade to an empty list.
class FoodDatabaseSearch
  Result = Data.define(:name, :brand, :serving_grams, :kcal, :protein_g, :carb_g, :fat_g, :code)

  SEARCH_ENDPOINT = "https://world.openfoodfacts.org/cgi/search.pl".freeze
  PRODUCT_ENDPOINT = "https://world.openfoodfacts.org/api/v2/product/".freeze
  USER_AGENT = "PerformanceOS/1.0 (training app; contact support@performance-os.app)".freeze
  FIELDS = "code,product_name,brands,nutriments".freeze
  BARCODE = /\A\d{8,14}\z/
  CACHE_TTL = 1.hour

  def initialize(query, limit: 20)
    @query = query.to_s.strip
    @limit = limit
  end

  def call
    return [] if @query.blank?

    if @query.match?(BARCODE)
      Rails.cache.fetch("food_barcode/#{@query}", expires_in: CACHE_TTL) { barcode_lookup }
    else
      Rails.cache.fetch("food_search/#{@limit}/#{@query.downcase}", expires_in: CACHE_TTL) { search }
    end
  rescue StandardError => error
    Rails.logger.warn("FoodDatabaseSearch failed for #{@query.inspect}: #{error.class}: #{error.message}")
    []
  end

  private

  def search
    body = get(search_uri)
    return [] unless body

    Array(JSON.parse(body)["products"]).filter_map { |product| build_result(product) }
  end

  def barcode_lookup
    body = get(product_uri(@query))
    return [] unless body

    data = JSON.parse(body)
    return [] unless data["status"].to_i == 1

    [ build_result(data["product"]) ].compact
  end

  def search_uri
    uri = URI(SEARCH_ENDPOINT)
    uri.query = URI.encode_www_form(
      search_terms: @query, search_simple: 1, action: "process",
      json: 1, page_size: @limit, fields: FIELDS
    )
    uri
  end

  def product_uri(code)
    uri = URI("#{PRODUCT_ENDPOINT}#{code}.json")
    uri.query = URI.encode_www_form(fields: FIELDS)
    uri
  end

  def get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 3
    http.read_timeout = 5

    response = http.get(uri.request_uri, "User-Agent" => USER_AGENT)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  end

  def build_result(product)
    return if product.blank?

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
