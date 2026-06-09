class WearableDevice < ApplicationRecord
  PLATFORMS = %w[ios_healthkit].freeze

  belongs_to :user
  has_many :wearable_samples, dependent: :destroy

  validates :platform, inclusion: { in: PLATFORMS }
  validates :external_id, :name, :token_digest, presence: true
  validates :external_id, uniqueness: { scope: :user_id }

  scope :active, -> { where(revoked_at: nil) }

  def self.issue_for!(user:, platform:, external_id:, name:)
    device = user.wearable_devices.find_or_initialize_by(external_id: external_id)
    raw_token = SecureRandom.urlsafe_base64(32)
    device.assign_attributes(
      platform: platform,
      name: name,
      token_digest: BCrypt::Password.create(raw_token),
      revoked_at: nil
    )
    device.save!
    [ device, "#{device.id}.#{raw_token}" ]
  end

  def authenticate_token(raw_token)
    return false if revoked_at? || raw_token.blank?

    BCrypt::Password.new(token_digest).is_password?(raw_token)
  end
end
