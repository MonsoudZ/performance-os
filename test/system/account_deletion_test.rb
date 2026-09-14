require "application_system_test_case"

class AccountDeletionTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.workout_sessions.create!(performed_at: 1.day.ago)
  end

  test "deleting an account asks twice and then signs you out" do
    sign_in @user
    visit edit_profile_path

    assert_text "Delete your account."
    fill_in "Confirm your password", with: "password"

    # The dialog is the only part of this flow that needs a browser, and it is
    # the last thing between a signed-in session and an irreversible delete.
    accept_confirm { click_on "Delete my account" }

    assert_current_path new_session_path
    assert_text "deleted"
    assert_nil User.find_by(id: @user.id)
  end

  test "dismissing the confirmation deletes nothing" do
    sign_in @user
    visit edit_profile_path
    fill_in "Confirm your password", with: "password"

    dismiss_confirm { click_on "Delete my account" }

    assert_current_path edit_profile_path
    assert User.exists?(@user.id)
  end
end
