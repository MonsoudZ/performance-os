require "application_system_test_case"

# A flash is fixed over the page, so how it goes away is the whole of it.
class FlashMessagesTest < ApplicationSystemTestCase
  test "the welcome notice sees itself out without covering the confirm banner" do
    visit new_registration_path
    fill_in "Email", with: "flash-system@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Create account"

    assert_text "Welcome to PerformanceOS"
    # Both were position: fixed at the same coordinates before the stack, so a
    # new account read one message printed over another.
    assert_selector ".flash-stack .flash", count: 2
    assert_no_overlap(*all(".flash-stack .flash").first(2))

    # Long enough to read, and then gone on its own.
    assert_no_text "Welcome to PerformanceOS", wait: 8
    # The standing one is not a message about something that just happened, so
    # it stays.
    assert_selector ".flash--alert"
  end

  test "a message can be closed before its timer runs out" do
    visit new_registration_path
    fill_in "Email", with: "flash-close@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Create account"

    assert_text "Welcome to PerformanceOS"
    within(".flash--notice") { find(".flash__close").click }

    assert_no_selector ".flash--notice"
    assert_no_text "Welcome to PerformanceOS"
  end

  # An explanation of what just went wrong must not be taken away from the
  # person still reading it.
  test "an error stays until it is closed" do
    visit new_session_path
    fill_in "Email", with: users(:one).email_address
    fill_in "Password", with: "wrong password"
    click_on "Sign in"

    assert_text "Try another email address or password"
    # Past the notice timer: an error must not time out the way a success does.
    sleep 6
    assert_text "Try another email address or password"

    within(".flash--alert") { find(".flash__close").click }
    assert_no_selector ".flash--alert"
  end

  private

  # Cuprite hands back a plain hash of the bounding box.
  def assert_no_overlap(first, second)
    boxes = [ first, second ].map(&:rect).sort_by { |box| box["y"] }
    ends_at = boxes.first["y"] + boxes.first["height"]

    assert_operator ends_at, :<=, boxes.last["y"] + 1,
      "two messages are drawn over each other: one ends at #{ends_at}, the next starts at #{boxes.last['y']}"
  end
end
