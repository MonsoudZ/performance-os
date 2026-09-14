require "test_helper"

# The flow exists to make a change reversible until it is proven. Most of these
# are about what must *not* happen to the live address.
class EmailChangeRequestTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { @user = users(:one) }

  test "a request parks the new address and leaves the live one alone" do
    result = request("new@example.com")

    assert_predicate result, :success?
    assert_equal "new@example.com", @user.reload.pending_email_address
    assert_equal "one@example.com", @user.email_address
  end

  test "it writes to the new address and warns the old one" do
    assert_enqueued_emails 2 do
      request("new@example.com")
    end
  end

  test "a wrong password changes nothing" do
    result = request("new@example.com", password: "not-the-password")

    assert_not_predicate result, :success?
    assert_nil @user.reload.pending_email_address
  end

  test "an address another account already holds is refused" do
    result = request(users(:two).email_address)

    assert_not_predicate result, :success?
    assert_match(/already in use/, result.error)
    assert_nil @user.reload.pending_email_address
  end

  test "asking for the address you already have is refused" do
    result = request(@user.email_address)

    assert_not_predicate result, :success?
    assert_match(/already your email address/, result.error)
  end

  test "a blank address is refused" do
    assert_not_predicate request(""), :success?
  end

  test "addresses are normalized, so case is not a second account" do
    request("  NEW@Example.COM ")

    assert_equal "new@example.com", @user.reload.pending_email_address
  end

  test "a change into a full mailbox is refused before any email is sent" do
    User::ACCOUNTS_PER_MAILBOX.times do |i|
      User.create!(email_address: "full+#{i}@example.com", password: "password123", available_equipment: %w[barbell])
    end

    result = nil
    assert_no_enqueued_emails do
      result = request("full+mine@example.com")
    end

    # Otherwise the change flow is the way around the cap.
    assert_not_predicate result, :success?
    assert_match(/as many accounts as it can hold/, result.error)
  end

  test "a change cannot be started when it could never be confirmed" do
    ActionMailer::Base.perform_deliveries = false

    result = request("new@example.com")

    # Fails closed, unlike new-account confirmation: refusing leaves the account
    # exactly as it was, while starting one would park a request forever.
    assert_not_predicate result, :success?
    assert_match(/not configured/, result.error)
    assert_nil @user.reload.pending_email_address
  ensure
    ActionMailer::Base.perform_deliveries = true
  end

  private

  def request(address, password: "password")
    EmailChangeRequest.new(@user, new_address: address, password: password).call
  end
end
