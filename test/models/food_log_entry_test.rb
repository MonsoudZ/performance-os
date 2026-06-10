require "test_helper"

class FoodLogEntryTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "accepts the known sources" do
    FoodLogEntry::SOURCES.each do |source|
      entry = build_entry(source: source)
      assert entry.valid?, "expected #{source.inspect} to be a valid source"
    end
  end

  test "rejects an unknown source" do
    entry = build_entry(source: "import")
    assert_not entry.valid?
    assert_includes entry.errors[:source], "is not included in the list"
  end

  private

  def build_entry(attributes)
    @user.food_log_entries.new({
      logged_at: Time.current,
      meal_type: "lunch",
      quantity_grams: 100,
      kcal: 100,
      protein_g: 10,
      carb_g: 10,
      fat_g: 5
    }.merge(attributes))
  end
end
