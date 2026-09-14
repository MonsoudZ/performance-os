require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "creates an account and signs the user in" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          email_address: "new@example.com",
          password: "password",
          password_confirmation: "password",
          unit_system: "metric",
          time_zone: "America/Denver"
        }
      }
    end

    assert_redirected_to onboarding_path
    assert cookies[:session_id]
    assert_equal "America/Denver", User.order(:created_at).last.time_zone
  end

  # Both of these are fixed over the page. They used to be fixed at the same
  # coordinates, so a new account read the welcome printed across the banner
  # telling it to confirm an address — and neither could be closed.
  test "the welcome notice and the confirm banner stack instead of colliding" do
    post registration_path, params: { user: {
      email_address: "stacked@example.com", password: "password123", password_confirmation: "password123"
    } }
    follow_redirect!

    assert_select ".flash-stack .flash", 2
    assert_select ".flash-stack .flash--notice", text: /Welcome to PerformanceOS/
    assert_select ".flash-stack .flash--alert", text: /Confirm stacked@example\.com/
  end

  test "the welcome notice can be closed and sees itself out" do
    post registration_path, params: { user: {
      email_address: "closable@example.com", password: "password123", password_confirmation: "password123"
    } }
    follow_redirect!

    assert_select ".flash--notice[data-controller=?]", "flash"
    assert_select ".flash--notice[data-flash-dismiss-after-value=?]", "5000"
    assert_select ".flash--notice .flash__close[data-action=?]", "flash#dismiss"
    # Announced rather than only drawn: a message fixed over the page is no use
    # to somebody who never hears it.
    assert_select ".flash--notice[role=?]", "status"
  end

  test "a new account is unconfirmed and is sent a confirmation" do
    assert_enqueued_emails 1 do
      register("fresh@example.com", from: "10.8.0.1")
    end

    user = User.find_by!(email_address: "fresh@example.com")
    assert_not_predicate user, :verified?
    # Signed in anyway: a new account can start logging straight away.
    assert cookies[:session_id]
    assert_redirected_to onboarding_path
  end

  test "a mailbox that is full cannot take another account" do
    User::ACCOUNTS_PER_MAILBOX.times do |i|
      User.create!(email_address: "full+#{i}@example.com", password: "password123", available_equipment: %w[barbell])
    end

    assert_no_difference "User.count" do
      # Sub-addressing is the cheap way around a unique index, and confirmation
      # does not catch it: every one of these lands in the same inbox.
      register("full+another@example.com", from: "10.7.0.1")
    end

    assert_response :unprocessable_entity
  end

  test "throttles an address that floods the sign-up form" do
    Rack::Attack::REGISTRATION_LIMIT.times { |i| register("flood-#{i}@example.com", from: "10.9.0.1") }

    assert_no_difference "User.count" do
      register("flood-last@example.com", from: "10.9.0.1")
    end

    assert_response :too_many_requests
  end

  test "the cap is per address, so one flood does not close the door on everyone" do
    Rack::Attack::REGISTRATION_LIMIT.times { |i| register("flood-#{i}@example.com", from: "10.9.0.1") }

    assert_difference "User.count", 1 do
      register("elsewhere@example.com", from: "10.9.0.2")
    end

    assert_redirected_to onboarding_path
  end

  test "a rejected sign-up still counts towards the cap" do
    # Otherwise the limit is trivially evaded by sending invalid payloads, which
    # cost the server the same.
    Rack::Attack::REGISTRATION_LIMIT.times { register("", from: "10.9.0.3") }

    register("valid@example.com", from: "10.9.0.3")

    assert_response :too_many_requests
  end

  private

  def register(email_address, from:)
    post registration_path,
      params: {
        user: {
          email_address: email_address,
          password: "password",
          password_confirmation: "password",
          unit_system: "metric",
          time_zone: "UTC"
        }
      },
      headers: { "REMOTE_ADDR" => from }
  end
end
