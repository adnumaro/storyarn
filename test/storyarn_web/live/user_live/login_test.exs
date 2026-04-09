defmodule StoryarnWeb.UserLive.LoginTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = LiveVue.Test.get_vue(view, name: "modules/auth/SignIn")
      assert vue.component == "modules/auth/SignIn"
      assert vue.props["login-action"] == "/users/log-in"
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

      vue = LiveVue.Test.get_vue(view, name: "modules/auth/SignIn")
      assert vue.props["local-mail-adapter"] == true
    after
      Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test)
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "passes email to Vue when logged in", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      vue = LiveVue.Test.get_vue(view, name: "modules/auth/SignIn")
      assert vue.props["email"] == user.email
      assert vue.props["readonly"] == true
    end
  end
end
