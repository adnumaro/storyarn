defmodule StoryarnWeb.SettingsLive.SecurityTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias StoryarnWeb.UserAuth

  defp get_security_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsSecurity")
  end

  defp get_settings_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  describe "Security settings page" do
    test "renders security settings Vue component", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/security")

      vue = get_security_vue(view)
      assert vue.component == "live/account/settings/AccountSettingsSecurity"
    end

    test "passes password-form prop", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/security")

      vue = get_security_vue(view)
      assert is_map(vue.props["password-form"])
    end

    test "passes current email and password action URL", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/security")

      vue = get_security_vue(view)
      assert vue.props["current-email"] == user.email
      assert vue.props["password-action"] == "/users/update-password"
    end

    test "passes trigger-submit=false initially", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings/security")

      vue = get_security_vue(view)
      assert vue.props["trigger-submit"] == false
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings/security")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "preserves the security destination when sudo mode has expired", %{conn: conn} do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

      conn =
        log_in_user(conn, user_fixture(), token_authenticated_at: stale_authenticated_at)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/users/settings/security")

      assert to == UserAuth.sudo_confirmation_path(~p"/users/settings/security")
    end

    test "keeps the page and password action inside the shared twenty-minute sudo window", %{
      conn: conn
    } do
      user = user_fixture()
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -19, :minute)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, token_authenticated_at: authenticated_at)
        |> live(~p"/users/settings/security")

      password = valid_user_password() <> " changed"

      render_click(view, "update_password", %{
        "user" => %{
          "email" => user.email,
          "password" => password,
          "password_confirmation" => password
        }
      })

      assert get_security_vue(view).props["trigger-submit"] == true
    end

    test "preserves a session-bound grant through the layout and password form", %{conn: conn} do
      user = user_fixture()
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)
      session_token = get_session(conn, :user_token)
      grant = UserAuth.issue_sudo_grant(user, session_token)
      path = UserAuth.with_sudo_grant(~p"/users/settings/security", grant)

      assert {:ok, view, _html} = live(conn, path)
      assert get_settings_layout_vue(view).props["sudo-grant"] == grant

      security_vue = get_security_vue(view)
      assert security_vue.props["sudo-grant"] == grant

      password = valid_user_password() <> " changed"

      render_click(view, "update_password", %{
        "user" => %{
          "email" => user.email,
          "password" => password,
          "password_confirmation" => password
        }
      })

      assert get_security_vue(view).props["trigger-submit"] == true
    end
  end

  describe "validate_password event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders errors with short password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_click(view, "validate_password", %{
        "user" => %{
          "password" => "too short",
          "password_confirmation" => "does not match"
        }
      })

      vue = get_security_vue(view)
      password_form = vue.props["password-form"]
      assert password_form["errors"] != %{} or password_form["valid"] == false
    end

    test "translates password errors using the user locale", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Storyarn.Accounts.update_user_profile(user, %{"locale" => "es"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/security")

      render_click(view, "validate_password", %{
        "user" => %{
          "password" => "",
          "password_confirmation" => ""
        }
      })

      vue = get_security_vue(view)
      password_form = vue.props["password-form"]

      assert ["no puede estar vacío"] = password_form["errors"]["password"]
    end
  end

  describe "update_password event" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sets trigger-submit=true on valid password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_click(view, "update_password", %{
        "user" => %{
          "email" => user.email,
          "password" => new_password,
          "password_confirmation" => new_password
        }
      })

      vue = get_security_vue(view)
      assert vue.props["trigger-submit"] == true
    end

    test "renders errors with invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      render_click(view, "update_password", %{
        "user" => %{
          "password" => "too short",
          "password_confirmation" => "does not match"
        }
      })

      vue = get_security_vue(view)
      password_form = vue.props["password-form"]
      assert password_form["errors"] != %{} or password_form["valid"] == false
      # trigger-submit should NOT be set on invalid data
      assert vue.props["trigger-submit"] == false
    end
  end
end
