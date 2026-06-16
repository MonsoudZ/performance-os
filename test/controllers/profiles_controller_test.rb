require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "edit renders the training profile form" do
    get edit_profile_path
    assert_response :success
    assert_select "form[action=?]", profile_path
  end

  test "update persists training profile fields" do
    patch profile_path, params: {
      user: {
        experience_level: "advanced",
        training_days_per_week: 5,
        available_equipment: [ "barbell", "dumbbell", "" ]
      }
    }

    assert_redirected_to edit_profile_path
    @user.reload
    assert_equal "advanced", @user.experience_level
    assert_equal 5, @user.training_days_per_week
    assert_equal %w[barbell dumbbell], @user.available_equipment # blank stripped
  end

  test "rejects clearing all equipment" do
    patch profile_path, params: { user: { available_equipment: [ "" ] } }

    assert_equal %w[barbell dumbbell machine bodyweight cable other], @user.reload.available_equipment
    assert_match(/equipment/i, flash[:alert])
  end

  test "still accepts the inline max-hr update" do
    patch profile_path, params: { user: { max_hr: 188 } }
    assert_equal 188, @user.reload.max_hr
  end
end
