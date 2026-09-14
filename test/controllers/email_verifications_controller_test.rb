require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "a confirmation link verifies the account without needing a session" do
    @user.update!(verified_at: nil)
    token = @user.generate_token_for(:email_verification)

    # The link arrives in an email client, which may carry no cookie. The token
    # is the proof.
    get email_verification_path(token)

    assert_redirected_to root_path
    assert_predicate @user.reload, :verified?
  end

  test "a link cannot be used twice" do
    @user.update!(verified_at: nil)
    token = @user.generate_token_for(:email_verification)
    get email_verification_path(token)

    get email_verification_path(token)

    assert_match(/expired or has already been used/, flash[:alert])
  end

  test "an expired link is refused" do
    @user.update!(verified_at: nil)
    token = @user.generate_token_for(:email_verification)

    travel(User::EMAIL_VERIFICATION_PERIOD + 1.hour) do
      get email_verification_path(token)

      assert_match(/expired/, flash[:alert])
      assert_not_predicate @user.reload, :verified?
    end
  end

  test "a forged link verifies nobody" do
    @user.update!(verified_at: nil)

    get email_verification_path("not-a-real-token")

    assert_redirected_to root_path
    assert_not_predicate @user.reload, :verified?
  end

  test "one account's link cannot verify another" do
    @user.update!(verified_at: nil)
    other = users(:two)
    other.update!(verified_at: nil)

    get email_verification_path(other.generate_token_for(:email_verification))

    assert_predicate other.reload, :verified?
    assert_not_predicate @user.reload, :verified?
  end

  test "a signed-in user can ask for another email" do
    @user.update!(verified_at: nil)
    sign_in_as(@user)

    assert_enqueued_emails 1 do
      post email_verifications_path
    end

    assert_match(/Confirmation sent/, flash[:notice])
  end

  test "asking again once confirmed sends nothing" do
    sign_in_as(@user)

    assert_no_enqueued_emails do
      post email_verifications_path
    end

    assert_match(/already confirmed/, flash[:notice])
  end

  test "a signed-out visitor cannot make the app send email" do
    assert_no_enqueued_emails do
      post email_verifications_path
    end

    assert_redirected_to new_session_path
  end
end
