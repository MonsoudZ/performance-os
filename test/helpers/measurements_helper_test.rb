require "test_helper"

class MeasurementsHelperTest < ActionView::TestCase
  include MeasurementsHelper

  teardown { Current.session = nil }

  test "renders kilograms for a metric user" do
    sign_in_as_unit_system(users(:one))

    assert_equal "kg", weight_unit
    assert_equal "102.5 kg", weight(102.5)
    assert_equal "102.5", weight_amount(102.5)
  end

  test "renders pounds for an imperial user" do
    sign_in_as_unit_system(users(:two))

    assert_equal "lb", weight_unit
    assert_equal "220.4623 lb", weight(100)
    assert_equal "220.4623", weight_amount(100)
  end

  test "falls back to kilograms with no signed-in user" do
    Current.session = nil

    assert_equal "kg", weight_unit
    assert_equal "100 kg", weight(100)
  end

  test "returns nothing for a missing weight rather than a bare unit" do
    sign_in_as_unit_system(users(:two))

    assert_nil weight(nil)
    assert_nil weight_amount(nil)
    assert_nil weight_field_value(nil)
  end

  test "form field values are converted into the unit the label claims" do
    sign_in_as_unit_system(users(:two))

    assert_equal "220.4623", weight_field_value(100)
    assert_equal "any", measurement_step, "a pinned step would forbid real entries"
    assert_equal "70.8661", length_field_value(180)
  end

  test "converts height for an imperial user" do
    sign_in_as_unit_system(users(:two))

    assert_equal "in", length_unit
    assert_equal "70.8661", length_amount(180)
  end

  test "rebuilds a progression headline in the reader's units" do
    sign_in_as_unit_system(users(:two))

    increase = {
      "status" => "increase",
      "headline" => "Add 2.5 kg next time",
      "current_weight_kg" => 100.0,
      "next_weight_kg" => 102.5
    }

    assert_equal "Add 5.5116 lb next time", progression_headline(increase)
  end

  test "rebuilds a deload headline in the reader's units" do
    sign_in_as_unit_system(users(:two))

    deload = { "status" => "deload", "headline" => "Deload to 90 kg", "next_weight_kg" => 90.0 }

    assert_equal "Deload to 198.416 lb", progression_headline(deload)
  end

  test "keeps the stored headline when a decision carries no weights" do
    sign_in_as_unit_system(users(:two))

    hold = { "status" => "hold", "headline" => "Keep the load" }
    partial = { "status" => "increase", "headline" => "Add 2.5 kg next time" }

    assert_equal "Keep the load", progression_headline(hold)
    assert_equal "Add 2.5 kg next time", progression_headline(partial),
      "an increase without both weights cannot be rebuilt, so the record stands"
  end

  test "rebuilds daily-plan lift headlines in the reader's units" do
    sign_in_as_unit_system(users(:two))

    assert_equal "225.9738 lb",
      lift_headline({ "action" => "increase", "headline" => "102.5 kg", "next_weight_kg" => 102.5 })
    assert_equal "225.9738 lb if warm-ups are crisp",
      lift_headline({ "action" => "conditional_increase", "headline" => "102.5 kg if warm-ups are crisp", "next_weight_kg" => 102.5 })
  end

  test "keeps a lift headline written before the rule carried the weight" do
    sign_in_as_unit_system(users(:two))

    assert_equal "102.5 kg", lift_headline({ "action" => "increase", "headline" => "102.5 kg" })
    assert_equal "Establish today’s baseline",
      lift_headline({ "action" => "establish", "headline" => "Establish today’s baseline" })
  end

  private

  def sign_in_as_unit_system(user)
    Current.session = user.sessions.create!
  end
end
