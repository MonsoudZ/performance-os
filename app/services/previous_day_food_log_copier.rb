class PreviousDayFoodLogCopier
  Result = Data.define(:created_entries, :source_count)

  def initialize(user, destination_date: user.local_date)
    @user = user
    @destination_date = destination_date
  end

  def call
    source_entries = user.food_log_entries
      .where(logged_at: user.local_day_range(destination_date.yesterday))
      .order(:logged_at, :id)
      .lock

    created_entries = FoodLogEntry.transaction do
      source_entries.filter_map { |entry| copy_entry(entry) }
    end

    Result.new(created_entries:, source_count: source_entries.size)
  end

  private

  attr_reader :user, :destination_date

  def copy_entry(entry)
    copied_entry = user.food_log_entries.find_or_initialize_by(copied_from_entry: entry)
    return if copied_entry.persisted?

    copied_entry.assign_attributes(
      food: entry.food,
      logged_at: destination_time(entry.logged_at),
      meal_type: entry.meal_type,
      quantity_grams: entry.quantity_grams,
      kcal: entry.kcal,
      protein_g: entry.protein_g,
      carb_g: entry.carb_g,
      fat_g: entry.fat_g,
      source: "copy"
    )
    copied_entry.save!
    copied_entry
  end

  def destination_time(source_time)
    local_time = source_time.in_time_zone(user.time_zone)
    zone = ActiveSupport::TimeZone[user.time_zone]

    zone.local(
      destination_date.year,
      destination_date.month,
      destination_date.day,
      local_time.hour,
      local_time.min,
      local_time.sec
    )
  end
end
