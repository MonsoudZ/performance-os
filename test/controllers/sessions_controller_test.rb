require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "throttles repeated login attempts for one email even across IPs" do
    Rack::Attack.reset!

    Rack::Attack::LOGIN_LIMIT.times do |i|
      post session_path,
        params: { email_address: @user.email_address, password: "wrong" },
        headers: { "REMOTE_ADDR" => "10.1.0.#{i + 1}" }
      assert_response :redirect
    end

    # Same account, fresh IP: the per-email throttle still trips where a per-IP
    # limit would not.
    post session_path,
      params: { email_address: @user.email_address, password: "wrong" },
      headers: { "REMOTE_ADDR" => "10.1.0.250" }

    assert_response :too_many_requests
  ensure
    Rack::Attack.reset!
  end
end
