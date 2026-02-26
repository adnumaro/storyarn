defmodule Storyarn.Accounts.ProfilesTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Accounts.Profiles

  import Storyarn.AccountsFixtures

  describe "change_user_profile/2" do
    test "returns a changeset for valid attrs" do
      user = user_fixture()
      changeset = Profiles.change_user_profile(user, %{display_name: "New Name"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns changeset with no changes when empty attrs" do
      user = user_fixture()
      changeset = Profiles.change_user_profile(user, %{})
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns changeset with default empty attrs" do
      user = user_fixture()
      changeset = Profiles.change_user_profile(user)
      assert %Ecto.Changeset{} = changeset
    end

    test "validates display_name length" do
      user = user_fixture()
      long_name = String.duplicate("a", 101)
      changeset = Profiles.change_user_profile(user, %{display_name: long_name})
      assert "should be at most 100 character(s)" in errors_on(changeset).display_name
    end

    test "validates avatar_url format" do
      user = user_fixture()
      changeset = Profiles.change_user_profile(user, %{avatar_url: "not-a-url"})
      assert errors_on(changeset).avatar_url != []
    end

    test "accepts valid avatar_url" do
      user = user_fixture()

      changeset =
        Profiles.change_user_profile(user, %{avatar_url: "https://example.com/avatar.png"})

      assert changeset.valid?
    end
  end

  describe "update_user_profile/2" do
    test "updates display name" do
      user = user_fixture()
      assert {:ok, updated} = Profiles.update_user_profile(user, %{display_name: "Jaime"})
      assert updated.display_name == "Jaime"
    end

    test "updates avatar url" do
      user = user_fixture()

      assert {:ok, updated} =
               Profiles.update_user_profile(user, %{avatar_url: "https://example.com/pic.png"})

      assert updated.avatar_url == "https://example.com/pic.png"
    end

    test "returns error for invalid attrs" do
      user = user_fixture()
      long_name = String.duplicate("a", 101)
      assert {:error, changeset} = Profiles.update_user_profile(user, %{display_name: long_name})
      assert errors_on(changeset).display_name != []
    end

    test "clears display name with nil" do
      user = user_fixture()
      {:ok, user} = Profiles.update_user_profile(user, %{display_name: "Jaime"})
      assert {:ok, updated} = Profiles.update_user_profile(user, %{display_name: nil})
      assert updated.display_name == nil
    end
  end

  describe "sudo_mode?/2" do
    test "returns true when authenticated recently" do
      user = user_fixture()
      user = %{user | authenticated_at: DateTime.utc_now()}
      assert Profiles.sudo_mode?(user)
    end

    test "returns false when authenticated long ago" do
      user = user_fixture()
      old_time = DateTime.utc_now() |> DateTime.add(-30, :minute)
      user = %{user | authenticated_at: old_time}
      refute Profiles.sudo_mode?(user)
    end

    test "returns false when authenticated_at is nil" do
      user = user_fixture()
      user = %{user | authenticated_at: nil}
      refute Profiles.sudo_mode?(user)
    end

    test "respects custom minutes parameter" do
      user = user_fixture()
      # Authenticated 5 minutes ago
      five_min_ago = DateTime.utc_now() |> DateTime.add(-5, :minute)
      user = %{user | authenticated_at: five_min_ago}

      # With 10-minute window, should be in sudo
      assert Profiles.sudo_mode?(user, -10)

      # With 3-minute window, should NOT be in sudo
      refute Profiles.sudo_mode?(user, -3)
    end

    test "boundary: exactly at the limit" do
      user = user_fixture()
      exactly_20_min_ago = DateTime.utc_now() |> DateTime.add(-20, :minute)
      user = %{user | authenticated_at: exactly_20_min_ago}
      # At exactly the boundary, should return false (not after)
      refute Profiles.sudo_mode?(user)
    end
  end
end
