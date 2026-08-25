defmodule Storyarn.Accounts.Authentication.Rules.SudoWindowTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts.Authentication.Rules.SudoWindow
  alias Storyarn.Platform.Shared.TimeHelpers

  describe "active?/2" do
    test "returns true when authenticated recently" do
      user = user_fixture()
      user = %{user | authenticated_at: TimeHelpers.now()}
      assert SudoWindow.active?(user)
    end

    test "returns false when authenticated long ago" do
      user = user_fixture()
      old_time = DateTime.add(TimeHelpers.now(), -30, :minute)
      user = %{user | authenticated_at: old_time}
      refute SudoWindow.active?(user)
    end

    test "returns false when authenticated_at is nil" do
      user = user_fixture()
      user = %{user | authenticated_at: nil}
      refute SudoWindow.active?(user)
    end

    test "respects custom minutes parameter" do
      user = user_fixture()
      five_min_ago = DateTime.add(TimeHelpers.now(), -5, :minute)
      user = %{user | authenticated_at: five_min_ago}

      assert SudoWindow.active?(user, -10)
      refute SudoWindow.active?(user, -3)
    end

    test "boundary: exactly at the limit" do
      user = user_fixture()
      exactly_20_min_ago = DateTime.add(TimeHelpers.now(), -20, :minute)
      user = %{user | authenticated_at: exactly_20_min_ago}

      refute SudoWindow.active?(user)
    end
  end
end
