require "test_helper"

# The export's spec is the complement of AccountDeletion: whatever erasure
# destroys, this hands back first. That symmetry is the point, so it is asserted
# rather than described.
class AccountExportTest < ActiveSupport::TestCase
  include AccountFixture

  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "everything deletion destroys has somewhere to land in the export" do
    sections = AccountExport.new(@user).call.keys

    missing = AccountFixture::ACCOUNT_MODELS.reject do |model|
      sections.include?(model.name.underscore.pluralize)
    end

    # User itself is the "profile" section; everything else maps by table name.
    assert_equal [], missing - [ User ],
      "these are erased on deletion but never handed back: #{missing.inspect}"
    assert_includes sections, "profile"
  end

  test "a populated account exports every section with something in it" do
    populate_account(@user)
    export = AccountExport.new(@user).call

    empty = export.except("export", "profile").select { |_name, rows| rows.blank? }

    assert_empty empty, "the fixture should populate every section, so an empty one is a gap"
    assert_equal AccountExport::FORMAT_VERSION, export.dig("export", "format_version")
  end

  test "credentials are never exported, whatever else is" do
    populate_account(@user)

    serialized = AccountExport.new(@user).to_json

    AccountExport::EXCLUDED_COLUMNS.each do |column|
      assert_no_match(/#{column}/, serialized, "#{column} is how the account is secured, not a fact about it")
    end
    assert_no_match(/password/i, serialized)
  end

  test "it exports one account and never another" do
    populate_account(@user)
    populate_account(@other)

    serialized = AccountExport.new(@user).to_json

    assert_no_match(/#{@other.email_address}/, serialized)
    assert_equal @user.email_address, AccountExport.new(@user).call.dig("profile", "email_address")
  end

  test "a set entry can be read back to the lift it was performed on" do
    populate_account(@user)
    export = AccountExport.new(@user).call

    entry = export["workout_sessions"].first["set_entries"].first
    exercise_ids = export["exercises"].map { |exercise| exercise["id"] }

    # Without this an exported set is a weight against an integer.
    assert_includes exercise_ids, entry["exercise_id"]
  end

  test "catalog lifts the account trained on come too, though deletion leaves them" do
    ExerciseCatalogImporter.new.call
    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise: squat, set_index: 1, weight_kg: 100, reps: 5, rir: 2)

    exported = AccountExport.new(@user).call["exercises"].map { |exercise| exercise["id"] }

    assert_includes exported, squat.id
  end

  test "a decision carries the evidence it cites" do
    parent = account_decision(@user, "daily_training")
    child = account_decision(@user, "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")

    exported = AccountExport.new(@user).call["coaching_decisions"]
    parent_row = exported.find { |row| row["id"] == parent.id }

    # A decision alone says what was recommended; the citations say what it was
    # built from, which is the whole claim the product makes.
    assert_equal [ { "decision_id" => child.id, "role" => "readiness" } ], parent_row["cites"]
    assert_equal [], exported.find { |row| row["id"] == child.id }["cites"]
  end

  test "measurements are exported at the precision they were stored" do
    @user.body_metrics.create!(measured_on: Date.current, weight_kg: "81.646627")

    exported = AccountExport.new(@user).call["body_metrics"].first

    # The export is a record, so it carries what was written rather than what the
    # profile would render.
    assert_equal "81.646627", exported["weight_kg"].to_s
  end

  test "an untouched account still produces a readable file" do
    export = AccountExport.new(@user).call

    assert_equal @user.email_address, export.dig("profile", "email_address")
    assert_nothing_raised { JSON.parse(AccountExport.new(@user).to_json) }
  end

  test "the filename is dated in the reader's own day" do
    @user.update!(time_zone: "America/Denver")

    assert_equal "performance-os-export-#{@user.local_date.iso8601}.json", AccountExport.new(@user).filename
  end

  private

  def populate(user)
    AccountDeletionTest.new(nil).send(:populate, user)
  end

  def decision(user, decision_type)
    user.coaching_decisions.create!(
      decision_type: decision_type, rule_key: "#{decision_type}.v1", rule_version: "1.0.0",
      inputs: {}, output: { "headline" => "Headline" }, citations: [], confidence: "high"
    )
  end
end
