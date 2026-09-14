require "test_helper"

class AccountExportsControllerTest < ActionDispatch::IntegrationTest
  include AccountFixture

  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "downloads the account as a dated JSON file" do
    populate_account(@user)

    get account_export_path

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/performance-os-export-#{@user.local_date.iso8601}\.json/, response.headers["Content-Disposition"])
  end

  test "the file parses and holds this account's records" do
    populate_account(@user)

    get account_export_path
    body = JSON.parse(response.body)

    assert_equal @user.email_address, body.dig("profile", "email_address")
    assert_predicate body["workout_sessions"], :any?
    assert_predicate body["coaching_decisions"], :any?
  end

  test "it never hands back a credential" do
    populate_account(@user)

    get account_export_path

    AccountExport::EXCLUDED_COLUMNS.each { |column| assert_no_match(/#{column}/, response.body) }
  end

  test "signing out closes the export" do
    sign_out

    get account_export_path

    assert_redirected_to new_session_path
  end

  test "one account cannot export another" do
    populate_account(users(:two))

    get account_export_path
    body = JSON.parse(response.body)

    # There is no id in the route to tamper with — the export reads Current.user
    # and nothing else — so this pins that it stays that way.
    assert_equal @user.id, body.dig("profile", "id")
    assert_no_match(/#{users(:two).email_address}/, response.body)
  end

  test "the profile page offers the export and the delete copy points at it" do
    get edit_profile_path

    assert_response :success
    assert_select "a[href=?]", account_export_path, minimum: 2
    assert_select ".panel--danger", text: /take a copy first/
  end
end
