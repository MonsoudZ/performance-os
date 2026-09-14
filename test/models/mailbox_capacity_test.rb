require "test_helper"

# The cap exists because email_address being unique says nothing about how many
# addresses reach one inbox.
class MailboxCapacityTest < ActiveSupport::TestCase
  test "a mailbox holds a household and no more" do
    User::ACCOUNTS_PER_MAILBOX.times { |i| assert_predicate build("shared+#{i}@example.com"), :valid? }
    User::ACCOUNTS_PER_MAILBOX.times { |i| create("shared+#{i}@example.com") }

    over = build("shared+one-too-many@example.com")

    assert_not_predicate over, :valid?
    assert_includes over.errors[:email_address], "already has as many accounts as it can hold"
  end

  test "sub-addressing does not buy a fresh allowance" do
    User::ACCOUNTS_PER_MAILBOX.times { |i| create("busy+#{i}@example.com") }

    assert_not_predicate build("busy@example.com"), :valid?
  end

  test "gmail dots do not either" do
    User::ACCOUNTS_PER_MAILBOX.times { |i| create("a.b.c+#{i}@gmail.com") }

    assert_not_predicate build("abc@googlemail.com"), :valid?
  end

  test "a different mailbox is unaffected" do
    User::ACCOUNTS_PER_MAILBOX.times { |i| create("busy+#{i}@example.com") }

    assert_predicate build("someone-else@example.com"), :valid?
  end

  test "the canonical mailbox is stored, not guessed at query time" do
    user = create("Me.Name+Lifting@GoogleMail.com")

    assert_equal "mename@gmail.com", user.canonical_email_address
    assert_equal "me.name+lifting@googlemail.com", user.email_address, "what was typed is what is stored"
  end

  test "an account does not count against its own move within a mailbox" do
    (User::ACCOUNTS_PER_MAILBOX - 1).times { |i| create("shared+#{i}@example.com") }
    mover = create("shared+mover@example.com")

    # The mailbox is full, but this account is already one of the occupants.
    mover.email_address = "shared+renamed@example.com"

    assert_predicate mover, :valid?
  end

  test "saving an untouched account in a full mailbox is not blocked" do
    users = Array.new(User::ACCOUNTS_PER_MAILBOX) { |i| create("shared+#{i}@example.com") }

    users.first.update!(training_days_per_week: 5)

    assert_equal 5, users.first.reload.training_days_per_week
  end

  private

  def build(email_address)
    User.new(email_address: email_address, password: "password123", available_equipment: %w[barbell])
  end

  def create(email_address)
    build(email_address).tap(&:save!)
  end
end
