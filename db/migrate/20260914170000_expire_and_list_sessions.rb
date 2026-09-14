class ExpireAndListSessions < ActiveRecord::Migration[8.1]
  # A session had no clock of its own: the cookie was permanent and the row
  # recorded only when it was created. `last_active_at` is what makes an idle
  # timeout possible, and what lets the sessions list say "last used" rather
  # than only "signed in".
  #
  # Defaulted in the database rather than the model because sessions are created
  # from several places — the controller, the test helper, fixtures — and a
  # session with no activity timestamp would read as instantly expired.
  def up
    add_column :sessions, :last_active_at, :datetime, default: -> { "CURRENT_TIMESTAMP" }

    # Existing sessions were last seen whenever their row last moved. created_at
    # is the floor for rows that never did.
    execute "UPDATE sessions SET last_active_at = COALESCE(updated_at, created_at) WHERE last_active_at IS NULL"
    change_column_null :sessions, :last_active_at, false

    # The sweep reads it across every user, and the list reads it per user.
    add_index :sessions, :last_active_at
  end

  def down
    remove_column :sessions, :last_active_at
  end
end
