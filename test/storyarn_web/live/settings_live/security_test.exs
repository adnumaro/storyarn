defmodule StoryarnWeb.SettingsLive.SecurityTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  defp get_security_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsSecurity")
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
