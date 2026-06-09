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

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal "America/Denver", User.order(:created_at).last.time_zone
  end
end
