defmodule StoryarnWeb.SettingsLive.ProfileTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias StoryarnWeb.UserAuth

  defp get_profile_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsProfile")
  end

  defp stale_login(conn, user) do
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
    log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)
  end

  describe "Profile settings page" do
    test "renders profile settings page as Vue component", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsProfile"
      assert has_element?(view, "#command-palette")
    end

    test "passes the profile form, the email and an active sudo state", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert is_map(vue.props["profile-form"])
      assert vue.props["email"] == user.email
      assert vue.props["sudo-active"] == true
      assert vue.props["save-status"] == "idle"
      assert vue.props["reauth"]["returnTo"] == "/users/settings"

      refute Map.has_key?(vue.props, "locale-options")
      refute Map.has_key?(vue.props, "email-form")
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "mounts locked instead of redirecting when sudo mode has expired", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> stale_login(user_fixture())
        |> live(~p"/users/settings")

      vue = get_profile_vue(view)
      assert vue.props["sudo-active"] == false
      assert vue.props["reauth"]["sudoHandoff"] == nil
      assert vue.props["reauth"]["triggerSubmit"] == false
    end

    test "re-authenticates in place with the right password", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> stale_login(user)
        |> live(~p"/users/settings")

      render_click(view, "confirm_access", %{"password" => "wrong password"})
      assert get_profile_vue(view).props["reauth"]["sudoHandoff"] == nil

      render_click(view, "confirm_access", %{"password" => valid_user_password()})

      vue = get_profile_vue(view)
      assert is_binary(vue.props["reauth"]["sudoHandoff"])
      assert vue.props["reauth"]["triggerSubmit"] == true
    end

    test "locks the page instead of saving when sudo mode has expired", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> stale_login(user)
        |> live(~p"/users/settings")

      html = render_click(view, "update_profile", %{"user" => %{"display_name" => "Blocked"}})

      assert html =~ "Confirm it&#39;s you to change these settings."
      refute Accounts.get_user!(user.id).display_name == "Blocked"
      refute_redirected(view)
    end

    test "preserves the email confirmation token when sudo mode has expired", %{conn: conn} do
      token = "email-change-token"
      conn = stale_login(conn, user_fixture())

      return_to = ~p"/users/settings/confirm-email/#{token}"
      assert {:error, {:live_redirect, %{to: to}}} = live(conn, return_to)
      assert to == UserAuth.sudo_confirmation_path(return_to)
    end

    test "opens and updates profile with a grant bound to the stale session", %{conn: conn} do
      user = user_fixture()
      conn = stale_login(conn, user)
      session_token = get_session(conn, :user_token)
      grant = UserAuth.issue_sudo_grant(user, session_token)
      path = UserAuth.with_sudo_grant(~p"/users/settings", grant)

      assert {:ok, view, _html} = live(conn, path)

      layout = LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
      assert layout.props["sudo-grant"] == grant
      assert get_profile_vue(view).props["sudo-active"] == true

      render_click(view, "update_profile", %{"user" => %{"display_name" => "Granted"}})
      assert Accounts.get_user!(user.id).display_name == "Granted"
    end
  end

  describe "update profile event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "saves the display name and reports the save", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "update_profile", %{"user" => %{"display_name" => "New Name"}})

      assert get_profile_vue(view).props["save-status"] == "saved"
      assert Accounts.get_user!(user.id).display_name == "New Name"
      refute_redirected(view)
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
      assert get_profile_vue(view).props["sudo-active"] == true
    end

    test "validates profile on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_click(view, "validate_profile", %{"user" => %{"display_name" => "Test"}})

      # Should not crash and Vue component still renders
      vue = get_profile_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsProfile"
    end
  end

  describe "request_email_change event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sends the confirmation link to the new address", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html =
        render_click(view, "request_email_change", %{"email" => "new.#{user.email}"})

      assert html =~ "A link to confirm your email change has been sent to the new address."
      assert Accounts.get_user!(user.id).email == user.email
    end

    test "keeps the current email when the new one is invalid", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      html = render_click(view, "request_email_change", %{"email" => "not-an-email"})

      refute html =~ "A link to confirm your email change has been sent"
      assert Accounts.get_user!(user.id).email == user.email
    end
  end
end
