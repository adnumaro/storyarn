defmodule StoryarnWeb.UserLive.AuthRedirectTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  describe "public auth pages" do
    setup :register_and_log_in_user

    test "redirects authenticated users away from registration links", %{conn: conn} do
      {:ok, {:registration_required, token}} =
        Accounts.prepare_invitation_user(unique_user_email())

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/register/#{token}")
      assert to =~ "/workspaces/"
    end

    test "redirects authenticated users away from public registration", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/register")
      assert to =~ "/workspaces/"
    end

    test "keeps confirm access available for authenticated users", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/users/confirm-access?return_to=/users/settings/security")

      assert has_element?(view, "#confirm-access-vue")

      vue =
        LiveVue.Test.get_vue(view,
          name: "live/auth/confirm-access/AuthConfirmAccessForm"
        )

      assert String.starts_with?(vue.props["back-url"], "/workspaces/")
      assert vue.props["confirm-action"] == "/users/confirm-access"
      assert vue.props["return-to"] == "/users/settings/security"
      assert is_binary(vue.props["csrf-token"])
      assert vue.props["sudo-handoff"] == nil
      assert vue.props["trigger-submit"] == false
    end

    test "falls back to profile for an unsafe return target", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/users/confirm-access?return_to=https%3A%2F%2Fexample.com")

      vue =
        LiveVue.Test.get_vue(view,
          name: "live/auth/confirm-access/AuthConfirmAccessForm"
        )

      assert String.starts_with?(vue.props["back-url"], "/workspaces/")
    end

    test "validates the password and prepares a session-bound rotation handoff", %{
      conn: conn,
      user: user
    } do
      token = get_session(conn, :user_token)
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      override_token_authenticated_at(token, stale_authenticated_at)

      {:ok, view, _html} =
        live(conn, ~p"/users/confirm-access?return_to=/users/settings/security")

      refute Accounts.sudo_mode?(elem(Accounts.get_user_by_session_token(token), 0))

      render_hook(view, "confirm_access", %{
        "password" => valid_user_password(),
        "return_to" => "/users/settings"
      })

      vue =
        LiveVue.Test.get_vue(view,
          name: "live/auth/confirm-access/AuthConfirmAccessForm"
        )

      handoff = vue.props["sudo-handoff"]
      assert is_binary(handoff)
      assert vue.props["trigger-submit"] == true
      assert vue.props["return-to"] == "/users/settings/security"

      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at == stale_authenticated_at
      refute StoryarnWeb.UserAuth.sudo_mode?(session_user)
      assert StoryarnWeb.UserAuth.sudo_handoff_valid?(session_user, token, handoff)
    end

    test "rejects an invalid password without navigating", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/confirm-access")

      render_hook(view, "confirm_access", %{"password" => "wrong password"})

      assert_reply(view, %{ok: false, error: "invalid_password"})
      assert has_element?(view, "#confirm-access-vue")
    end

    test "redirects to login when the session token is deleted after mount", %{conn: conn} do
      token = get_session(conn, :user_token)
      {:ok, view, _html} = live(conn, ~p"/users/confirm-access")
      :ok = Accounts.delete_user_session_token(token)

      render_hook(view, "confirm_access", %{"password" => "wrong password"})

      assert {"/users/log-in", flash} = assert_redirect(view)
      assert flash["error"] == "Your session has expired. Please log in again."
    end

    test "rate limits sudo independently for the current user and IP", %{conn: conn} do
      original = Application.get_env(:storyarn, RateLimiter)
      Application.put_env(:storyarn, RateLimiter, enabled: true)

      on_exit(fn -> Application.put_env(:storyarn, RateLimiter, original || []) end)

      {:ok, view, _html} = live(conn, ~p"/users/confirm-access")

      for _ <- 1..5 do
        render_hook(view, "confirm_access", %{"password" => "wrong password"})
        assert_reply(view, %{ok: false, error: "invalid_password"})
      end

      render_hook(view, "confirm_access", %{"password" => "wrong password"})
      assert_reply(view, %{ok: false, error: "rate_limited"})
    end
  end

  describe "confirm access" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/users/confirm-access")

      assert flash["error"] == "You must log in to access this page."
    end
  end
end
