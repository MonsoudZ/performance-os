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
