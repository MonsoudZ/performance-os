class MarkCatalogStaples < ActiveRecord::Migration[8.1]
  # Whether ProgramGenerator may prescribe this lift on its own.
  #
  # The generator picks the first compound in a muscle group, ranked by modality
  # then name, so every exercise added to the catalog silently competed to become
  # somebody's program. Growing the catalog from 49 to 173 made a barbell clean
  # outrank a barbell row for "back" on alphabetical order alone — an explosive
  # lift prescribed with double progression, which is not a thing to ask anyone
  # to add 2.5 kg to every week.
  #
  # Opt-in rather than opt-out, so the next exercise somebody adds is available
  # to log and to choose by hand without changing what the generator builds.
  def change
    add_column :exercises, :staple, :boolean, null: false, default: false
    add_index :exercises, :staple, where: "user_id IS NULL AND staple"
  end
end
