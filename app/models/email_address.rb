# Reduces an address to the mailbox it actually lands in, so that counting
# accounts per person means something.
#
# `email_address` is already unique, so the same string cannot sign up twice.
# What it cannot see is that one mailbox accepts an unlimited number of
# addresses: sub-addressing (`me+1@`, `me+2@`) is supported by every major
# provider, and Gmail additionally ignores dots in the local part. Confirmation
# does not help — all of them deliver to the same inbox, so all of them confirm.
#
# This is used for *counting only*. What a user typed is what is stored, what
# they log in with and where mail is sent; nothing here rewrites an address.
module EmailAddress
  # Providers documented as ignoring dots in the local part. Deliberately a short
  # list rather than a rule applied everywhere: at most hosts `a.b@` and `ab@`
  # are two different people, and merging them would refuse a stranger's sign-up
  # because of a name that happens to look similar.
  DOT_INSENSITIVE_DOMAINS = {
    "gmail.com" => "gmail.com",
    "googlemail.com" => "gmail.com"
  }.freeze

  module_function

  def canonical(address)
    local, domain = address.to_s.strip.downcase.split("@", 2)
    return address.to_s.strip.downcase if domain.blank?

    # Sub-addressing is a convention rather than a standard, but it is a near
    # universal one, and the cost of being wrong is a household sharing a
    # mailbox counting as one account rather than several.
    local = local.split("+", 2).first.to_s

    if (canonical_domain = DOT_INSENSITIVE_DOMAINS[domain])
      local = local.delete(".")
      domain = canonical_domain
    end

    "#{local}@#{domain}"
  end
end
