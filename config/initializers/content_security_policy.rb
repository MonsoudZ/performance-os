# Be sure to restart your server when you modify this file.

# Application-wide Content Security Policy. User-controlled strings (food names,
# exercise names, notes) are rendered into Turbo/ERB views, so this is the
# defense-in-depth layer against injected scripts.
#
# Shipped in REPORT-ONLY first: violations are reported but not enforced, so we
# can confirm nothing legitimate is blocked before flipping
# `content_security_policy_report_only` to false to enforce.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    # The dashboard sets a CSS custom property via an inline style attribute
    # (score ring). Allow inline style *attributes* only — not inline <style>
    # blocks, and never inline scripts.
    policy.style_src_attr :unsafe_inline
    policy.connect_src :self # same-origin Action Cable websocket
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # Nonce the importmap/Turbo inline <script> tags so script-src can stay :self
  # without 'unsafe-inline'.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end
