class AddAuthenticationToUsers < ActiveRecord::Migration[8.1]
  def up
    rename_column :users, :email, :email_address
    add_column :users, :password_digest, :string
    execute "UPDATE users SET password_digest = '!' WHERE password_digest IS NULL"
    change_column_null :users, :password_digest, false
  end

  def down
    remove_column :users, :password_digest
    rename_column :users, :email_address, :email
  end
end
