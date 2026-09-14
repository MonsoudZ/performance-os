require "test_helper"

class EmailChangeConfirmationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(pending_email_address: "new@example.com")
    @token = @user.generate_token_for(:email_change)
  end

  test "confirming moves the address and clears the request" do
    result = EmailChangeConfirmation.new(@token).call

    assert_predicate result, :success?
    assert_equal "new@example.com", @user.reload.email_address
    assert_nil @user.pending_email_address
  end

  test "confirming a new address also confirms the account" do
    @user.update!(verified_at: nil)

    EmailChangeConfirmation.new(@token).call

    # They just proved they receive mail there, which is the only question
    # confirmation asks.
    assert_predicate @user.reload, :verified?
  end

  test "a token cannot be used twice" do
    EmailChangeConfirmation.new(@token).call

    result = EmailChangeConfirmation.new(@token).call

    assert_equal :expired, result.error
  end

  test "cancelling the request kills the token" do
    @user.update!(pending_email_address: nil)

    assert_equal :expired, EmailChangeConfirmation.new(@token).call.error
  end

  test "a token issued for one address cannot confirm another" do
    @user.update!(pending_email_address: "somewhere-else@example.com")

    # The token carries the address it was issued for, so changing the request
    # invalidates it rather than redirecting it.
    assert_equal :expired, EmailChangeConfirmation.new(@token).call.error
    assert_equal "one@example.com", @user.reload.email_address
  end

  test "an expired token is refused" do
    travel(User::EMAIL_CHANGE_PERIOD + 1.hour) do
      assert_equal :expired, EmailChangeConfirmation.new(@token).call.error
      assert_equal "one@example.com", @user.reload.email_address
    end
  end

  test "a forged token confirms nothing" do
    assert_equal :expired, EmailChangeConfirmation.new("not-a-token").call.error
  end

  test "losing the race to the address cancels the request rather than half-applying it" do
    # Somebody registers it between the request and the click.
    users(:two).update!(email_address: "new@example.com")

    result = EmailChangeConfirmation.new(@token).call

    assert_equal :taken, result.error
    assert_equal "one@example.com", @user.reload.email_address
    assert_nil @user.pending_email_address
  end
end
