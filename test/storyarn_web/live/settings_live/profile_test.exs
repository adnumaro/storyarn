defmodule StoryarnWeb.SettingsLive.ProfileTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts

  defp get_profile_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsProfile")
  end

  describe "Profile settings page" do
    test "renders profile settings page as Vue component", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsProfile"
    end

    test "passes profile_form prop without email change props", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert is_map(vue.props["profile-form"])
      refute Map.has_key?(vue.props, "email-form")
      refute Map.has_key?(vue.props, "current-email")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update profile event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "can update display name without redirecting", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html = render_click(view, "update_profile", %{"user" => %{"display_name" => "New Name"}})

      assert html =~ "Profile updated successfully."
      assert Accounts.get_user!(user.id).display_name == "New Name"
    end

    test "can update profile locale without redirecting", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html = render_click(view, "update_profile", %{"user" => %{"locale" => "es"}})

      assert html =~ "Perfil actualizado exitosamente."
      assert Accounts.get_user!(user.id).locale == "es"
    end

    test "validates profile on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "validate_profile", %{"user" => %{"display_name" => "Test"}})

      # Should not crash and Vue component still renders
      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsProfile"
    end
  end
end
