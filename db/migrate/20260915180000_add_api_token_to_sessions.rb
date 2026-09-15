class AddApiTokenToSessions < ActiveRecord::Migration[8.1]
  def change
    # Nullable: a browser session has a cookie and no token, and most rows are
    # browser sessions. The digest is unique so a lookup is one indexed read.
    #
    # There is deliberately no expiry column. A token belongs to the session
    # that issued it and dies with it, on the two clocks that row already has —
    # so ending a device from /profile/edit ends its token too, and a third
    # clock cannot drift out of step with the other two.
    add_column :sessions, :api_token_digest, :string
    add_index :sessions, :api_token_digest, unique: true
  end
end
