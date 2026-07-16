defmodule StoryarnWeb.SettingsLive.ProfileTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias StoryarnWeb.UserAuth

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

      assert vue.props["locale-options"] == [
               %{
                 "flagCode" => "gb",
                 "label" => "English",
                 "languageTag" => "en",
                 "shortLabel" => "EN",
                 "value" => "en"
               },
               %{
                 "flagCode" => "es",
                 "label" => "Español",
                 "languageTag" => "es",
                 "shortLabel" => "ES",
                 "value" => "es"
               }
             ]

      refute Map.has_key?(vue.props, "email-form")
      refute Map.has_key?(vue.props, "current-email")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "preserves the profile destination when sudo mode has expired", %{conn: conn} do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

      conn =
        log_in_user(conn, user_fixture(), token_authenticated_at: stale_authenticated_at)

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/users/settings")
      assert to == UserAuth.sudo_confirmation_path(~p"/users/settings")
    end

    test "preserves the email confirmation token when sudo mode has expired", %{conn: conn} do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      token = "email-change-token"

      conn =
        log_in_user(conn, user_fixture(), token_authenticated_at: stale_authenticated_at)

      return_to = ~p"/users/settings/confirm-email/#{token}"
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, return_to)
      assert to == UserAuth.sudo_confirmation_path(return_to)
    end

    test "opens and updates profile with a grant bound to the stale session", %{conn: conn} do
      user = user_fixture()
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)
      session_token = get_session(conn, :user_token)
      grant = UserAuth.issue_sudo_grant(user, session_token)
      path = UserAuth.with_sudo_grant(~p"/users/settings", grant)

      assert {:ok, view, _html} = live(conn, path)

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
      assert layout.props["sudo-grant"] == grant

      render_click(view, "update_profile", %{"user" => %{"display_name" => "Granted"}})
      assert Accounts.get_user!(user.id).display_name == "Granted"
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

    test "keeps recent sudo authentication across consecutive profile updates", %{
      conn: conn,
      user: user
    } do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -19, :minute)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, token_authenticated_at: authenticated_at)
        |> live(~p"/users/settings")

      render_click(view, "update_profile", %{"user" => %{"display_name" => "First save"}})
      refute_redirected(view)

      render_click(view, "update_profile", %{"user" => %{"display_name" => "Second save"}})
      refute_redirected(view)

      assert Accounts.get_user!(user.id).display_name == "Second save"
      assert get_profile_vue(view).component == "live/account/settings/AccountSettingsProfile"
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
