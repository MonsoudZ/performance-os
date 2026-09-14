class RecordErrorReports < ActiveRecord::Migration[8.1]
  # An operational log of what the app failed at, in the app's own database.
  #
  # Deliberately not associated with `users`: these are records about the system
  # rather than about a person, so they are neither exported with an account nor
  # destroyed with one, and adding them here does not touch AccountFixture. The
  # user an error happened to is kept in `context` as an id, so a deleted account
  # leaves an integer behind rather than anything about them.
  def change
    create_table :error_reports do |t|
      # One row per distinct failure, not per occurrence: an error hitting every
      # user at once should be one thing to look at, with a count on it.
      t.string :fingerprint, null: false
      t.string :error_class, null: false
      t.text :message
      t.text :backtrace
      t.string :source
      t.string :severity, null: false, default: "error"
      t.boolean :handled, null: false, default: false
      t.jsonb :context, null: false, default: {}
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      # Null until somebody has been told. Kept separate from last_seen_at so a
      # recurring error does not re-notify on every occurrence.
      t.datetime :last_notified_at

      t.timestamps
    end

    add_index :error_reports, :fingerprint, unique: true
    add_index :error_reports, :last_seen_at
    add_check_constraint :error_reports, "occurrences > 0", name: "error_reports_occurrences_check"
    add_check_constraint :error_reports, "severity IN ('error', 'warning', 'info')",
      name: "error_reports_severity_check"
  end
end
