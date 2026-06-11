require "test_helper"

class NextBlockSuggestionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "no suggestion while a block is active" do
    @user.mesocycles.create!(started_on: Date.current - 3.days, weeks: 4)

    assert_nil NextBlockSuggestion.new(@user).call
  end

  test "no suggestion when the user has never run a block" do
    assert_nil NextBlockSuggestion.new(@user).call
  end

  test "suggests a block mirroring the most recent one, starting today" do
    @user.mesocycles.create!(name: "Block 1", started_on: Date.current - 40.days, weeks: 4, deload_week: 4)

    suggestion = NextBlockSuggestion.new(@user).call

    assert suggestion
    assert_equal 4, suggestion.weeks
    assert_equal 4, suggestion.deload_week
    assert_equal Date.current, suggestion.started_on
    assert_equal "Block 2", suggestion.name
  end

  test "carries the focus forward" do
    @user.mesocycles.create!(name: "Block 1", started_on: Date.current - 40.days, weeks: 4, focus: "power")

    assert_equal "power", NextBlockSuggestion.new(@user).call.focus
  end

  test "recently_ended? is true just after a block ends" do
    @user.mesocycles.create!(started_on: Date.current - 30.days, ended_on: Date.current - 2.days, weeks: 4)

    assert NextBlockSuggestion.new(@user).recently_ended?
  end

  test "recently_ended? is false for a long-finished block" do
    @user.mesocycles.create!(started_on: Date.current - 100.days, weeks: 4) # ended ~72 days ago

    assert_not NextBlockSuggestion.new(@user).recently_ended?
  end
end
