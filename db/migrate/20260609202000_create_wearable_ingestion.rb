class CreateWearableIngestion < ActiveRecord::Migration[8.1]
  def change
    create_table :wearable_devices do |table|
      table.references :user, null: false, foreign_key: true
      table.string :platform, null: false
      table.string :external_id, null: false
      table.string :name, null: false
      table.string :token_digest, null: false
      table.datetime :last_synced_at
      table.datetime :revoked_at

      table.timestamps
    end

    add_index :wearable_devices, [ :user_id, :external_id ], unique: true
    add_check_constraint :wearable_devices,
      "platform IN ('ios_healthkit')",
      name: "wearable_devices_platform_check"

    create_table :wearable_samples do |table|
      table.references :user, null: false, foreign_key: true
      table.references :wearable_device, null: false, foreign_key: true
      table.string :external_id, null: false
      table.string :metric_type, null: false
      table.datetime :started_at, null: false
      table.datetime :ended_at
      table.decimal :value, precision: 10, scale: 3
      table.string :unit, null: false
      table.jsonb :metadata, null: false, default: {}

      table.timestamps
    end

    add_index :wearable_samples, [ :wearable_device_id, :external_id ], unique: true
    add_index :wearable_samples, [ :user_id, :metric_type, :started_at ]
    add_check_constraint :wearable_samples,
      "metric_type IN ('hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_asleep')",
      name: "wearable_samples_metric_type_check"
    add_check_constraint :wearable_samples,
      "value IS NULL OR value >= 0",
      name: "wearable_samples_value_check"
  end
end
