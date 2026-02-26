defmodule StoryarnWeb.UserLive.LoginTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Log in with email"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert Storyarn.Repo.get_by!(Storyarn.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      # User is redirected to their default workspace
      assert redirected_to(conn) =~ "/workspaces/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "user login - magic link rate limited" do
    test "shows rate limited error when too many requests", %{conn: conn} do
      # Temporarily enable rate limiting for this test
      Application.put_env(:storyarn, Storyarn.RateLimiter, enabled: true)

      # Use a unique email to avoid cross-test interference
      unique_email = "ratelimit_#{System.unique_integer([:positive])}@example.com"

      # Submit magic link requests until rate limited (limit is 3 per minute)
      Enum.each(1..3, fn _ ->
        {:ok, lv, _html} = live(conn, ~p"/users/log-in")

        form(lv, "#login_form_magic", user: %{email: unique_email})
        |> render_submit()
      end)

      # The 4th request should be rate limited
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: unique_email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Too many requests"
    after
      # Restore original config
      Application.put_env(:storyarn, Storyarn.RateLimiter, enabled: false)
    end
  end

  describe "local mail adapter info" do
    test "shows local mail adapter info when adapter is Local", %{conn: conn} do
      # Temporarily set the mailer adapter to Local
      Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "local mail adapter"
      assert html =~ "the mailbox"
      assert html =~ "/dev/mailbox"
    after
      Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test)
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end
end
