require "test_helper"

# Reducing an address to its mailbox is only useful if it is neither too eager
# nor too shy: merging two strangers refuses a legitimate sign-up, and merging
# nothing leaves the cap trivially evaded.
class EmailAddressTest < ActiveSupport::TestCase
  test "a plain address is its own mailbox" do
    assert_equal "me@example.com", EmailAddress.canonical("me@example.com")
  end

  test "case and surrounding space do not make a second mailbox" do
    assert_equal "me@example.com", EmailAddress.canonical("  Me@Example.COM ")
  end

  test "sub-addressing resolves to the mailbox it lands in" do
    assert_equal "me@example.com", EmailAddress.canonical("me+one@example.com")
    assert_equal "me@example.com", EmailAddress.canonical("me+two+three@example.com")
  end

  test "gmail ignores dots, so the canonical form does too" do
    assert_equal "mename@gmail.com", EmailAddress.canonical("me.name@gmail.com")
    assert_equal "mename@gmail.com", EmailAddress.canonical("me.name+lifting@googlemail.com")
  end

  test "dots elsewhere are left alone, because elsewhere they mean something" do
    # At most hosts a.b@ and ab@ are two different people. Merging them would
    # refuse a stranger's sign-up over a name that happens to look similar.
    assert_equal "me.name@example.com", EmailAddress.canonical("me.name@example.com")
    assert_not_equal EmailAddress.canonical("ab@example.com"), EmailAddress.canonical("a.b@example.com")
  end

  test "nonsense in does not raise" do
    assert_equal "", EmailAddress.canonical("")
    assert_equal "", EmailAddress.canonical(nil)
    assert_equal "not-an-address", EmailAddress.canonical("not-an-address")
  end
end
