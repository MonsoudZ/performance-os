# What the native client is told about the person using it.
#
# Measurements go out in the units the database stores — kilograms, centimetres
# — exactly like the account export, and for the same reason: this is a record
# being transported, not a rendering. `unit_system` rides along so the client
# knows what to show, and the conversion happens at the client's own display
# boundary rather than being baked into the wire format.
#
# Nothing here is a credential. The password digest, the verification and
# change tokens and the pending address all stay on the server.
class UserSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    {
      id: user.id,
      email_address: user.email_address,
      verified: user.verified_at.present?,
      unit_system: user.unit_system,
      time_zone: user.time_zone,
      local_date: user.local_date.iso8601,
      experience_level: user.experience_level,
      training_days_per_week: user.training_days_per_week,
      available_equipment: user.available_equipment,
      sex: user.sex,
      birth_date: user.birth_date&.iso8601,
      height_cm: user.height_cm&.to_f,
      max_hr: user.max_hr
    }
  end

  private

  attr_reader :user
end
