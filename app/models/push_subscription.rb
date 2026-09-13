class PushSubscription < ApplicationRecord
  # The endpoint is supplied by the client and the server makes an outbound
  # request to it on a schedule, so an unchecked value turns the hourly reminder
  # job into a server-side request forgery: any signed-in user could point it at
  # cloud metadata, an internal admin service, or a host they control and have
  # the app reach it from inside the network. The response never comes back to
  # them, but the request still lands.
  #
  # Push endpoints come from a small, known set of vendor services, so an
  # allow-list is both practical and the only check that holds up — filtering by
  # IP range would not survive a hostname that resolves somewhere else after the
  # check (CVE-2026-80213 is exactly that bug, in resolv).
  #
  # Matched on the URL host, either exactly or as a subdomain. Set
  # WEB_PUSH_ALLOWED_HOSTS to a comma-separated list to add a provider without a
  # deploy.
  VENDOR_PUSH_HOSTS = %w[
    fcm.googleapis.com
    push.services.mozilla.com
    web.push.apple.com
    notify.windows.com
  ].freeze

  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true
  validate :endpoint_belongs_to_a_push_service

  def self.allowed_push_hosts
    extra = ENV.fetch("WEB_PUSH_ALLOWED_HOSTS", "").split(",").map { |host| host.strip.downcase }.compact_blank
    VENDOR_PUSH_HOSTS + extra
  end

  def self.allowed_push_host?(host)
    return false if host.blank?

    # A trailing dot is a valid absolute FQDN and would otherwise dodge the match.
    normalized = host.downcase.delete_suffix(".")
    allowed_push_hosts.any? { |allowed| normalized == allowed || normalized.end_with?(".#{allowed}") }
  end

  private

  def endpoint_belongs_to_a_push_service
    return if endpoint.blank?

    uri = URI.parse(endpoint)
    return if uri.is_a?(URI::HTTPS) && self.class.allowed_push_host?(uri.host)

    errors.add(:endpoint, "is not a recognized push service URL")
  rescue URI::InvalidURIError
    errors.add(:endpoint, "is not a valid URL")
  end
end
