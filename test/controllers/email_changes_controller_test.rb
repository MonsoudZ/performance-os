require "test_helper"

class EmailChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "the profile offers a change and says the old address survives it" do
    get edit_profile_path

    assert_response :success
    assert_select "form[action=?] input[name=email_address]", email_changes_path
    assert_select "form[action=?] input[name=password][type=password]", email_changes_path
    assert_select ".evidence-note", text: /typo costs nothing/
  end

  test "requesting a change parks it and says what is still true" do
    post email_changes_path, params: { email_address: "new@example.com", password: "password" }

    assert_redirected_to edit_profile_path
    assert_match(/Confirm the change at new@example\.com/, flash[:notice])
    assert_match(/keeps one@example\.com/, flash[:notice])
    assert_equal "one@example.com", @user.reload.email_address
  end

  test "a wrong password says so and changes nothing" do
    post email_changes_path, params: { email_address: "new@example.com", password: "wrong" }

    assert_match(/password is not right/, flash[:alert])
    assert_nil @user.reload.pending_email_address
  end

  test "the profile shows a pending change and offers to cancel it" do
    @user.update!(pending_email_address: "new@example.com")

    get edit_profile_path

    assert_select ".evidence-note", text: /Waiting on new@example\.com/
    assert_select "form[action=?]", cancel_email_change_path
  end

  test "cancelling clears the request" do
    @user.update!(pending_email_address: "new@example.com")

    delete cancel_email_change_path

    assert_nil @user.reload.pending_email_address
    assert_match(/cancelled/, flash[:notice])
  end

  test "the confirmation link works without a session" do
    @user.update!(pending_email_address: "new@example.com")
    token = @user.generate_token_for(:email_change)
    sign_out

    get email_change_path(token)

    assert_equal "new@example.com", @user.reload.email_address
    assert_match(/now new@example\.com/, flash[:notice])
  end

  test "an expired link says so and moves nothing" do
    @user.update!(pending_email_address: "new@example.com")
    token = @user.generate_token_for(:email_change)

    travel(User::EMAIL_CHANGE_PERIOD + 1.hour) do
      get email_change_path(token)

      assert_match(/expired/, flash[:alert])
      assert_equal "one@example.com", @user.reload.email_address
    end
  end

  test "a signed-out visitor cannot start a change" do
    sign_out

    post email_changes_path, params: { email_address: "new@example.com", password: "password" }

    assert_redirected_to new_session_path
  end

  test "the banner asks for the address being moved to, not the one being left" do
    @user.update!(verified_at: nil, pending_email_address: "new@example.com")

    get edit_profile_path

    # Asking them to confirm an address they are in the middle of leaving would
    # be two contradictory instructions at once.
    assert_select ".flash--alert", text: /Confirm new@example\.com to finish moving/
    assert_select "form[action=?]", email_verifications_path, count: 0
  end
end
