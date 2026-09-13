require "test_helper"
require "capybara/cuprite"

# Locates a Chrome binary so these run on a developer's machine, in the dev
# container, and on a CI runner without anyone setting CHROME_BIN.
module SystemTestBrowser
  CANDIDATES = [
    "/opt/pw-browsers/chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  ].freeze

  # nil lets Ferrum fall back to its own detection, which covers anything this
  # list misses.
  def self.path
    ENV["CHROME_BIN"].presence || CANDIDATES.find { |candidate| File.executable?(candidate) }
  end
end

# Browser-driven tests, for the behaviour that only exists once JavaScript runs:
# the workout logger's rows, its live volume readout, Turbo's morph refreshes.
# Controller tests cover what the server renders; these cover what the page does
# afterwards.
#
# Cuprite speaks CDP straight to Chrome. Selenium would need a chromedriver whose
# major version matches the installed Chrome, which turns every Chrome update
# into a broken build for no benefit here.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [ 1400, 1400 ], options: {
    browser_path: SystemTestBrowser.path,
    headless: true,
    process_timeout: 30,
    timeout: 30,
    browser_options: {
      "no-sandbox" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil
    }
  }

  # Capybara's own server must be reachable; WebMock is otherwise global.
  setup { WebMock.disable_net_connect!(allow_localhost: true) }

  private

  # Signs in through the real form. A system test cannot reach for the signed
  # cookie the integration tests set, and driving the form is what a user does.
  def sign_in(user, password: "password")
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: password
    click_on "Sign in"
    assert_no_current_path new_session_path, wait: 5
  end

  # Number inputs keep their prefilled value unless cleared first, so this makes
  # an assertion about what was typed rather than about a merge.
  def set_number(field, value)
    field.set("")
    field.set(value.to_s)
  end
end
