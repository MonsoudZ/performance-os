require "test_helper"

class MesocycleTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "current_week, deload, and phase track the date within the block" do
    block = @user.mesocycles.create!(started_on: Date.new(2026, 6, 1), weeks: 4, deload_week: 4)

    assert_equal 1, block.current_week(Date.new(2026, 6, 1))
    assert_equal 1, block.current_week(Date.new(2026, 6, 7))
    assert_equal 2, block.current_week(Date.new(2026, 6, 8))
    assert_equal 4, block.current_week(Date.new(2026, 6, 22))

    assert block.deload?(Date.new(2026, 6, 22))
    assert_equal "deload", block.phase(Date.new(2026, 6, 22))
    assert_not block.deload?(Date.new(2026, 6, 8))
    assert_equal "accumulation", block.phase(Date.new(2026, 6, 8))
  end

  test "active_on respects the start, natural end, and early end" do
    block = @user.mesocycles.create!(started_on: Date.new(2026, 6, 1), weeks: 4) # natural end 6/28

    assert_includes @user.mesocycles.active_on(Date.new(2026, 6, 15)), block
    assert_not_includes @user.mesocycles.active_on(Date.new(2026, 5, 31)), block
    assert_not_includes @user.mesocycles.active_on(Date.new(2026, 6, 29)), block
  end

  test "deload week must be within the block length" do
    assert_not @user.mesocycles.new(started_on: Date.current, weeks: 4, deload_week: 5).valid?
  end

  test "focus caps the accumulation set bonus" do
    date = Date.new(2026, 6, 1)
    week5 = date + 28

    assert_equal 3, Mesocycle.new(started_on: date, weeks: 6, focus: "hypertrophy").accumulation_set_bonus(week5)
    assert_equal 1, Mesocycle.new(started_on: date, weeks: 6, focus: "strength").accumulation_set_bonus(week5)
  end

  test "rejects an unknown focus" do
    assert_not @user.mesocycles.new(started_on: Date.current, weeks: 4, focus: "cardio").valid?
  end
end
