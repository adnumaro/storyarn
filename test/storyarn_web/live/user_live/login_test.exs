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
      assert vue.props["login-action"] == "/users/log-in?locale=en"
      assert vue.props["forgot-password-url"] == "/users/reset-password?locale=en"
      assert vue.props["register-url"] == "/users/register?locale=en"
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
    test "login page links to public registration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = get_login_vue(view)
      assert vue.props["register-url"] == "/users/register?locale=en"
    end

    test "keeps an explicit Spanish handoff throughout auth navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in?locale=es")

      vue = get_login_vue(view)
      assert vue.props["login-action"] == "/users/log-in?locale=es"
      assert vue.props["forgot-password-url"] == "/users/reset-password?locale=es"
      assert vue.props["register-url"] == "/users/register?locale=es"
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
