class AddVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :verified_at, :datetime

    # Accounts that predate verification are treated as verified. They were
    # created when the app asked nothing of them, and locking them out of a
    # feature they never agreed to is a worse failure than trusting an address
    # nobody ever confirmed.
    execute "UPDATE users SET verified_at = created_at WHERE verified_at IS NULL"
  end

  def down
    remove_column :users, :verified_at
  end
end
