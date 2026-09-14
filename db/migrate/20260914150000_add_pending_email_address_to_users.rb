class AddPendingEmailAddressToUsers < ActiveRecord::Migration[8.1]
  # A requested address is held here until it is confirmed, rather than written
  # over the live one. Swapping first would mean a typo costs the account every
  # route back into it — password resets would go to an address that does not
  # exist — and would let anyone holding a session take the account outright.
  #
  # Not unique: two people may both want an address, and only one can ever
  # confirm it, because email_address is unique and that is the constraint that
  # actually decides. A unique index here would also leak whether an address is
  # already spoken for.
  def change
    add_column :users, :pending_email_address, :string
  end
end
