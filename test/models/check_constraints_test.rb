require "test_helper"

# The lists that live in Ruby constants are also enforced by check constraints,
# and the two have to agree. Postgres prints a constraint back in its own normal
# form rather than the form the migration wrote, so db/schema.rb's text for these
# is not something to read as the rule — this is. Inserting past the model is
# deliberate: the validation is not what is under test here.
class CheckConstraintsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @device = @user.wearable_devices.create!(
      name: "Probe", platform: "ios_healthkit", external_id: "probe-device", token_digest: "x" * 64
    )
  end

  test "every metric type the app knows about is accepted by the database" do
    WearableSample::METRIC_UNITS.each do |metric_type, unit|
      # A failure here means METRIC_UNITS gained an entry without a migration.
      assert_nothing_raised do
        insert_sample(metric_type: metric_type, unit: unit, external_id: "ok-#{metric_type}")
      end
    end

    assert_equal WearableSample::METRIC_UNITS.size, @user.wearable_samples.count
  end

  test "a metric type the app does not know about is rejected by the database" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      insert_sample(metric_type: "blood_pressure", unit: "mmHg", external_id: "nope")
    end

    assert_match(/wearable_samples_metric_type_check/, error.message)
  end

  test "every expenditure basis the app writes is accepted by the database" do
    ExpenditureEstimator::BASES.each_with_index do |basis, offset|
      # A failure here means BASES gained an entry without a migration.
      assert_nothing_raised do
        insert_estimate(basis: basis, on: Date.current - offset)
      end
    end
  end

  test "an expenditure basis the app does not write is rejected by the database" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      insert_estimate(basis: "guesswork", on: Date.current)
    end

    assert_match(/expenditure_estimates_basis_check/, error.message)
  end

  private

  def insert_sample(metric_type:, unit:, external_id:)
    WearableSample.connection.execute(<<~SQL)
      INSERT INTO wearable_samples
        (user_id, wearable_device_id, external_id, metric_type, unit, started_at, created_at, updated_at)
      VALUES
        (#{@user.id}, #{@device.id}, #{quote(external_id)}, #{quote(metric_type)}, #{quote(unit)}, now(), now(), now())
    SQL
  end

  def insert_estimate(basis:, on:)
    ExpenditureEstimate.connection.execute(<<~SQL)
      INSERT INTO expenditure_estimates (user_id, estimate_date, basis, confidence, estimated_tdee)
      VALUES (#{@user.id}, #{quote(on.iso8601)}, #{quote(basis)}, 'low', 2500)
    SQL
  end

  def quote(value) = ActiveRecord::Base.connection.quote(value)
end
