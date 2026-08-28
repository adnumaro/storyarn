defmodule Storyarn.Accounts.Identity.Commands.ProfileTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts.Identity.Commands.Profile

  describe "change_user_profile/2" do
    test "returns a changeset for valid attrs" do
      user = user_fixture()
      changeset = Profile.change_user_profile(user, %{display_name: "New Name"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns changeset with no changes when empty attrs" do
      user = user_fixture()
      changeset = Profile.change_user_profile(user, %{})
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns changeset with default empty attrs" do
      user = user_fixture()
      changeset = Profile.change_user_profile(user)
      assert %Ecto.Changeset{} = changeset
    end

    test "validates display_name length" do
      user = user_fixture()
      long_name = String.duplicate("a", 101)
      changeset = Profile.change_user_profile(user, %{display_name: long_name})
      assert "should be at most 100 character(s)" in errors_on(changeset).display_name
    end

    test "validates avatar_url format" do
      user = user_fixture()
      changeset = Profile.change_user_profile(user, %{avatar_url: "not-a-url"})
      assert errors_on(changeset).avatar_url != []
    end

    test "accepts valid avatar_url" do
      user = user_fixture()

      changeset =
        Profile.change_user_profile(user, %{avatar_url: "https://example.com/avatar.png"})

      assert changeset.valid?
    end
  end

  describe "update_user_profile/2" do
    test "updates display name" do
      user = user_fixture()
      assert {:ok, updated} = Profile.update_user_profile(user, %{display_name: "Jaime"})
      assert updated.display_name == "Jaime"
    end

    test "updates avatar url" do
      user = user_fixture()

      assert {:ok, updated} =
               Profile.update_user_profile(user, %{avatar_url: "https://example.com/pic.png"})

      assert updated.avatar_url == "https://example.com/pic.png"
    end

    test "returns error for invalid attrs" do
      user = user_fixture()
      long_name = String.duplicate("a", 101)
      assert {:error, changeset} = Profile.update_user_profile(user, %{display_name: long_name})
      assert errors_on(changeset).display_name != []
    end

    test "clears display name with nil" do
      user = user_fixture()
      {:ok, user} = Profile.update_user_profile(user, %{display_name: "Jaime"})
      assert {:ok, updated} = Profile.update_user_profile(user, %{display_name: nil})
      assert updated.display_name == nil
    end
  end
end
