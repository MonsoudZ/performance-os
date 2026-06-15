class ExercisePrescriptionSuperseder
  ATTRIBUTES = %w[
    rep_min
    rep_max
    target_rir_min
    target_rir_max
    increment_kg
    working_sets
    progression_model
  ].freeze

  def initialize(prescription, effective_on:)
    @prescription = prescription
    @effective_on = effective_on
  end

  def call(attributes)
    replacement_attributes = prescription.attributes.slice(*ATTRIBUTES).merge(attributes.to_h.stringify_keys)

    return update_unhistorical_target(replacement_attributes) if prescription.started_on >= effective_on

    replacement = prescription.user.exercise_prescriptions.new(
      replacement_attributes.merge(
        exercise: prescription.exercise,
        started_on: effective_on
      )
    )
    replacement.validate!

    ApplicationRecord.transaction do
      prescription.lock!
      raise ActiveRecord::RecordInvalid, prescription unless prescription.ended_on.nil?

      prescription.update!(ended_on: effective_on - 1.day)
      replacement.save!
    end

    replacement
  end

  private

  attr_reader :prescription, :effective_on

  def update_unhistorical_target(attributes)
    prescription.update!(attributes)
    prescription
  end
end
