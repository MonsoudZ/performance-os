class AddCanonicalEmailAddressToUsers < ActiveRecord::Migration[8.1]
  # The mailbox an address lands in, so accounts can be counted per person
  # rather than per string. See EmailAddress for why the two differ.
  #
  # Not unique — the point is to allow a few per mailbox and no more, which is a
  # validation rather than an index. Indexed because every sign-up counts against
  # it.
  def up
    add_column :users, :canonical_email_address, :string
    add_index :users, :canonical_email_address

    backfill
    change_column_null :users, :canonical_email_address, false
  end

  def down
    remove_column :users, :canonical_email_address
  end

  private

  # Spelled out rather than calling EmailAddress.canonical: a migration has to
  # keep describing the change it made after the rule moves on. Frozen here as
  # it stood when this ran.
  def backfill
    select_rows("SELECT id, email_address FROM users").each do |id, address|
      normalized = address.to_s.strip.downcase
      local, domain = normalized.split("@", 2)

      # An address with no domain cannot be reduced to a mailbox, but it still
      # needs a value — the column is about to stop accepting nulls.
      canonical =
        if domain.blank?
          normalized
        else
          local = local.split("+", 2).first.to_s
          if %w[gmail.com googlemail.com].include?(domain)
            local = local.delete(".")
            domain = "gmail.com"
          end
          "#{local}@#{domain}"
        end

      execute(<<~SQL.squish)
        UPDATE users SET canonical_email_address = #{connection.quote(canonical)}
        WHERE id = #{connection.quote(id)}
      SQL
    end
  end
end
