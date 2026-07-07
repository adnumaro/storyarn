defmodule StoryarnWeb.UserLive.LoginTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  defp get_login_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/auth/login/AuthLoginForm")
  end

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = get_login_vue(view)
      assert vue.component == "live/auth/login/AuthLoginForm"
      assert vue.props["login-action"] == "/users/log-in"
      assert vue.props["forgot-password-url"] == "/users/reset-password"
      assert is_map(vue.props["form"])
      assert vue.props["trigger-submit"] == false
    end

    test "passes invalid credentials as form error", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.fetch_flash([])
        |> Phoenix.Controller.put_flash(:login_error, "Invalid email or password")
        |> Phoenix.Controller.put_flash(:email, "typed@example.com")

      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = get_login_vue(view)
      form = vue.props["form"]

      assert form["values"]["email"] == "typed@example.com"
      assert form["errors"]["password"] == ["Invalid email or password"]
      assert vue.props["trigger-submit"] == false
    end

    test "keeps invalid credentials inside the LiveView form", %{conn: conn} do
      user = set_password(user_fixture())
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      render_click(view, "log_in", %{
        "user" => %{"email" => user.email, "password" => "invalid_password"}
      })

      vue = get_login_vue(view)
      form = vue.props["form"]

      assert form["values"]["email"] == user.email
      assert form["errors"]["password"] == ["Invalid email or password"]
      assert vue.props["trigger-submit"] == false
      refute vue.props["login-token"]
    end

    test "valid credentials arm the hidden session form", %{conn: conn} do
      user = set_password(user_fixture())
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      render_click(view, "log_in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

      vue = get_login_vue(view)

      assert vue.props["trigger-submit"] == true
      assert is_binary(vue.props["login-token"])
    end
  end

  describe "login navigation" do
    test "login page does not link to registration in beta mode", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      refute html =~ "Sign up"
      refute html =~ "Register"
    end
  end

  describe "local mail adapter info" do
    test "passes local-mail-adapter=true to Vue when adapter is Local", %{conn: conn} do
      Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local)

      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = get_login_vue(view)
      assert vue.props["local-mail-adapter"] == true
    after
      Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test)
    end
  end

  describe "public auth gating" do
    setup :register_and_log_in_user

    test "redirects authenticated users away from login", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/log-in")
      assert to =~ "/workspaces/"
    end
  end
end
