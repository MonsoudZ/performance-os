require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "enforces a content security policy with a usable script nonce" do
    get root_path

    assert_response :success

    # Enforced, not report-only.
    header = response.headers["Content-Security-Policy"]
    assert header.present?, "expected an enforced CSP header"
    assert_nil response.headers["Content-Security-Policy-Report-Only"]

    assert_includes header, "default-src 'self'"
    assert_includes header, "object-src 'none'"
    assert_includes header, "frame-ancestors 'none'"
    assert_includes header, "connect-src 'self'"

    # The importmap/Turbo inline scripts must carry the same non-empty nonce the
    # header allows, otherwise script-src 'self' would block them.
    nonce = header[/script-src 'self' 'nonce-([^']+)'/, 1]
    assert nonce.present?, "expected a non-empty script nonce in #{header.inspect}"
    assert_select "script[type='importmap'][nonce=?]", nonce

    # Every inline (non-src) script must carry a nonce or the enforced policy
    # blocks it. importmap emits the importmap JSON, the module entrypoint, and
    # the es-module-shims loader.
    inline_unnonced = css_select("script").reject { |s| s["src"] || s["nonce"].present? }
    assert_empty inline_unnonced, "un-nonced inline scripts would be blocked: #{inline_unnonced.map { |s| s['type'] }}"
  end

  test "styles stay same-origin, with a nonce for Turbo's progress bar" do
    get root_path

    header = response.headers["Content-Security-Policy"]

    # Turbo signs its progress-bar <style> with the csp-nonce meta tag. Without
    # this the element is refused and navigations show no loading indicator.
    style_nonce = header[/style-src 'self' 'nonce-([^']+)'/, 1]
    assert style_nonce.present?, "expected a style nonce in #{header.inspect}"
    assert_equal header[/script-src 'self' 'nonce-([^']+)'/, 1], style_nonce,
      "Turbo reads one nonce from the meta tag, so both directives must accept it"
    assert_select "meta[name='csp-nonce'][content=?]", style_nonce

    # The nonce must not have smuggled in blanket inline styles.
    assert_not_includes header, "style-src 'self' 'unsafe-inline'"
    # Inline style attributes stay allowed — the dashboard score ring needs them.
    assert_includes header, "style-src-attr 'unsafe-inline'"
  end
end
