class LetABlockOwnItsScheme < ActiveRecord::Migration[8.1]
  # Targets used to be rewritten in place when a block started — every active
  # prescription superseded to the focus's preset scheme. They are composed at
  # read time now, so a target says whether it takes its rep range, effort and
  # set count from the block or keeps its own.
  #
  # Defaulting to true is the behaviour the "Apply scheme" button existed to
  # produce, so an existing target that was applied keeps the numbers it has and
  # a target that was never applied starts following the block it is inside.
  # Anyone who wants their own range back unticks it on the target.
  def change
    add_column :exercise_prescriptions, :follows_block_scheme, :boolean, null: false, default: true
  end
end
