require "test_helper"

class FoodDatabaseSearchTest < ActiveSupport::TestCase
  SEARCH_URL = "https://world.openfoodfacts.org/cgi/search.pl".freeze
  SEARCH_PATH = %r{\Ahttps://world\.openfoodfacts\.org/cgi/search\.pl}.freeze # any query
  SAMPLE_BODY = {
    "products" => [
      {
        "code" => "111",
        "product_name" => "Greek Yogurt",
        "brands" => "Fage, Total",
        "nutriments" => {
          "energy-kcal_100g" => 59, "proteins_100g" => 10.3,
          "carbohydrates_100g" => 3.6, "fat_100g" => 0.4
        }
      },
      { "code" => "222", "product_name" => "", "brands" => "X",
        "nutriments" => { "energy-kcal_100g" => 100 } }, # blank name -> dropped
      { "code" => "333", "product_name" => "No Macros", "brands" => "Y",
        "nutriments" => {} } # no kcal -> dropped
    ]
  }.to_json

  setup { Rails.cache.clear }

  test "requests Open Food Facts with the expected query and headers" do
    stub = stub_request(:get, SEARCH_URL)
      .with(
        query: {
          "search_terms" => "greek yogurt",
          "search_simple" => "1",
          "action" => "process",
          "json" => "1",
          "page_size" => "20",
          "fields" => "code,product_name,brands,nutriments"
        },
        headers: { "User-Agent" => /\APerformanceOS\// }
      )
      .to_return(status: 200, body: SAMPLE_BODY, headers: { "Content-Type" => "application/json" })

    FoodDatabaseSearch.new("greek yogurt").call

    assert_requested stub
  end

  test "passes the configured limit as page_size" do
    stub_request(:get, SEARCH_PATH).to_return(status: 200, body: SAMPLE_BODY)

    FoodDatabaseSearch.new("yogurt", limit: 5).call

    assert_requested :get, SEARCH_URL, query: hash_including("page_size" => "5")
  end

  test "maps products to per-100g macro rows and drops incomplete ones" do
    stub_request(:get, SEARCH_PATH).to_return(status: 200, body: SAMPLE_BODY)

    results = FoodDatabaseSearch.new("greek yogurt").call

    assert_equal 1, results.size
    result = results.first
    assert_equal "Greek Yogurt", result.name
    assert_equal "Fage", result.brand # first brand only
    assert_equal 59.0, result.kcal
    assert_equal 10.3, result.protein_g
    assert_equal 100, result.serving_grams
    assert_equal "111", result.code
  end

  test "a blank query never touches the network" do
    assert_equal [], FoodDatabaseSearch.new("   ").call
    assert_not_requested :get, SEARCH_URL
  end

  test "degrades to an empty list on a non-success response" do
    stub_request(:get, SEARCH_PATH).to_return(status: 503, body: "<html>unavailable</html>")

    assert_equal [], FoodDatabaseSearch.new("yogurt").call
  end

  test "degrades to an empty list on a timeout" do
    stub_request(:get, SEARCH_PATH).to_timeout

    assert_equal [], FoodDatabaseSearch.new("yogurt").call
  end
end
