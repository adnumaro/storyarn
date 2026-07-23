defmodule StoryarnWeb.UserSessionControllerTest do
  use StoryarnWeb.ConnCase, async: false

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias StoryarnWeb.UserAuth

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      # User is redirected to their default workspace
      assert redirected_to(conn) =~ "/workspaces/"

      # Now do a logged in request to settings and assert on the menu
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_storyarn_web_user_remember_me"]
      # User is redirected to their default workspace
      assert redirected_to(conn) =~ "/workspaces/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "logs the user in with a validated LiveView login token", %{conn: conn, user: user} do
      user = set_password(user)
      session_nonce = "originating-browser-session"
      login_token = StoryarnWeb.UserLoginToken.sign_user(user, session_nonce)

      conn =
        conn
        |> init_test_session(login_handoff_nonce: session_nonce)
        |> post(~p"/users/log-in", %{
          "user" => %{"_login_token" => login_token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) =~ "/workspaces/"
    end

    test "rejects a LiveView login token replayed from another browser session", %{conn: conn, user: user} do
      user = set_password(user)
      login_token = StoryarnWeb.UserLoginToken.sign_user(user, "originating-browser-session")

      conn =
        conn
        |> init_test_session(login_handoff_nonce: "attacker-browser-session")
        |> post(~p"/users/log-in", %{
          "user" => %{"_login_token" => login_token}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :login_error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "ignores a blank LiveView login token when credentials are present", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "_login_token" => "",
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) =~ "/workspaces/"
    end

    test "rejects invalid LiveView login token as form error", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"_login_token" => "invalid"}
        })

      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Phoenix.Flash.get(conn.assigns.flash, :login_error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects authenticated users away from normal login POST", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) =~ "/workspaces/"
      refute Phoenix.Flash.get(conn.assigns.flash, :login_error)
    end

    test "redirects to login page with inline form error on invalid credentials", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Phoenix.Flash.get(conn.assigns.flash, :login_error) == "Invalid email or password"
      assert Phoenix.Flash.get(conn.assigns.flash, :email) == user.email
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/confirm-access" do
    test "rotates only the current browser into a fresh twenty-minute sudo session", %{
      conn: conn,
      user: user
    } do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)
      old_session_token = get_session(conn, :user_token)
      handoff = UserAuth.issue_sudo_handoff(user, old_session_token)

      conn =
        post(conn, ~p"/users/confirm-access", %{
          "sudo_handoff" => handoff,
          "return_to" => "/users/settings/security"
        })

      new_session_token = get_session(conn, :user_token)

      assert redirected_to(conn) == "/users/settings/security"
      refute new_session_token == old_session_token

      assert {new_session_user, _inserted_at} =
               Accounts.get_user_by_session_token(new_session_token)

      assert UserAuth.sudo_mode?(new_session_user)

      assert {old_session_user, _inserted_at} =
               Accounts.get_user_by_session_token(old_session_token)

      refute UserAuth.sudo_mode?(old_session_user)

      conn = get(conn, ~p"/users/settings/tutorials")
      assert html_response(conn, 200)

      conn = get(recycle(conn), ~p"/users/settings/security")
      assert html_response(conn, 200)
    end

    test "rejects a handoff from another session without rotating the current session", %{
      conn: conn,
      user: user
    } do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)
      current_session_token = get_session(conn, :user_token)
      other_session_token = Accounts.generate_user_session_token(user)
      invalid_handoff = UserAuth.issue_sudo_handoff(user, other_session_token)

      conn =
        post(conn, ~p"/users/confirm-access", %{
          "sudo_handoff" => invalid_handoff,
          "return_to" => "/users/settings/security"
        })

      assert redirected_to(conn) ==
               UserAuth.sudo_confirmation_path("/users/settings/security")

      assert get_session(conn, :user_token) == current_session_token

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Your access confirmation has expired."
    end

    test "rejects an unsafe return target", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      session_token = get_session(conn, :user_token)
      handoff = UserAuth.issue_sudo_handoff(user, session_token)

      conn =
        post(conn, ~p"/users/confirm-access", %{
          "sudo_handoff" => handoff,
          "return_to" => "https://example.com/steal-session"
        })

      assert redirected_to(conn) == "/users/settings"
    end
  end

  describe "POST /users/update-password" do
    test "accepts the same twenty-minute sudo window as the settings LiveView", %{
      conn: conn,
      user: user
    } do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -19, :minute)
      new_password = valid_user_password() <> " changed"

      conn =
        conn
        |> log_in_user(user, token_authenticated_at: authenticated_at)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == "/users/settings/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully!"
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "goes directly to confirmation when the sudo window has expired", %{
      conn: conn,
      user: user
    } do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

      conn =
        conn
        |> log_in_user(user, token_authenticated_at: authenticated_at)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      assert redirected_to(conn) ==
               UserAuth.sudo_confirmation_path("/users/settings/security")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Please re-authenticate to change your password."
    end

    test "accepts a signed grant bound to the stale current session", %{conn: conn, user: user} do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      new_password = valid_user_password() <> " granted"
      conn = log_in_user(conn, user, token_authenticated_at: authenticated_at)
      session_token = get_session(conn, :user_token)
      grant = UserAuth.issue_sudo_grant(user, session_token)

      conn =
        post(conn, ~p"/users/update-password", %{
          "sudo_grant" => grant,
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == "/users/settings/security"
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "redirects an invalid granted password POST without revoking the session", %{
      conn: conn,
      user: user
    } do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: authenticated_at)
      session_token = get_session(conn, :user_token)
      grant = UserAuth.issue_sudo_grant(user, session_token)

      conn =
        post(conn, ~p"/users/update-password", %{
          "sudo_grant" => grant,
          "user" => %{
            "email" => user.email,
            "password" => "short",
            "password_confirmation" => "different"
          }
        })

      assert redirected_to(conn) ==
               UserAuth.with_sudo_grant(~p"/users/settings/security", grant)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to update password."
      assert get_session(conn, :user_token) == session_token
      assert Accounts.get_user_by_session_token(session_token)
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "rejects a grant issued for another session", %{conn: conn, user: user} do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      conn = log_in_user(conn, user, token_authenticated_at: authenticated_at)
      other_session_token = Accounts.generate_user_session_token(user)
      grant = UserAuth.issue_sudo_grant(user, other_session_token)

      conn =
        post(conn, ~p"/users/update-password", %{
          "sudo_grant" => grant,
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      assert redirected_to(conn) ==
               UserAuth.sudo_confirmation_path("/users/settings/security")
    end

    test "replaces the session after a password change even when login is rate limited", %{
      conn: conn,
      user: user
    } do
      original_rate_limiter_config = Application.get_env(:storyarn, RateLimiter)
      Application.put_env(:storyarn, RateLimiter, enabled: true)

      on_exit(fn ->
        Application.put_env(:storyarn, RateLimiter, original_rate_limiter_config || [])
      end)

      unique_ip = System.unique_integer([:positive])
      third_octet = rem(div(unique_ip, 254), 254) + 1
      fourth_octet = rem(unique_ip, 254) + 1
      remote_ip = {192, 0, third_octet, fourth_octet}
      ip_address = remote_ip |> :inet.ntoa() |> to_string()

      for _ <- 1..5, do: assert(:ok = RateLimiter.check_login(ip_address))
      assert {:error, :rate_limited} = RateLimiter.check_login(ip_address)

      authenticated_at = DateTime.add(DateTime.utc_now(:second), -19, :minute)
      new_password = valid_user_password() <> " replacement"

      conn =
        conn
        |> Map.put(:remote_ip, remote_ip)
        |> log_in_user(user, token_authenticated_at: authenticated_at)

      old_session_token = get_session(conn, :user_token)

      conn =
        post(conn, ~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      new_session_token = get_session(conn, :user_token)

      assert redirected_to(conn) == "/users/settings/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully!"
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
      refute new_session_token == old_session_token
      refute Accounts.get_user_by_session_token(old_session_token)

      assert {session_user, _inserted_at} =
               Accounts.get_user_by_session_token(new_session_token)

      assert UserAuth.sudo_mode?(session_user)
      assert {:error, :rate_limited} = RateLimiter.check_login(ip_address)
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
