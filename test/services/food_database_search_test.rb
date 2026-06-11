require "test_helper"

class FoodDatabaseSearchTest < ActiveSupport::TestCase
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

  test "maps products to per-100g macro rows and drops incomplete ones" do
    results = search_returning("yogurt-a", SAMPLE_BODY)

    assert_equal 1, results.size
    result = results.first
    assert_equal "Greek Yogurt", result.name
    assert_equal "Fage", result.brand # first brand only
    assert_equal 59.0, result.kcal
    assert_equal 10.3, result.protein_g
    assert_equal 100, result.serving_grams
    assert_equal "111", result.code
  end

  test "returns nothing for a blank query without calling the API" do
    # If fetch were reached it would hit the network; a blank query must not.
    assert_equal [], FoodDatabaseSearch.new("   ").call
  end

  test "degrades to an empty list when the request fails" do
    search = FoodDatabaseSearch.new("yogurt-b")
    search.define_singleton_method(:fetch) { raise "network down" }

    assert_equal [], search.call
  end

  test "degrades to an empty list on a non-success response (nil body)" do
    assert_equal [], search_returning("yogurt-c", nil)
  end

  private

  # Overrides the private HTTP fetch with a canned body (no Minitest::Mock in
  # this build), then runs the real parse/map pipeline.
  def search_returning(query, body)
    search = FoodDatabaseSearch.new(query)
    search.define_singleton_method(:fetch) { body }
    search.call
  end
end
