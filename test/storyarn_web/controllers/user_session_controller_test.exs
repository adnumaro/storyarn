defmodule StoryarnWeb.UserSessionControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures

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
      login_token = StoryarnWeb.UserLoginToken.sign_user(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"_login_token" => login_token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) =~ "/workspaces/"
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

    test "confirmed access uses current user email when form email is absent", %{conn: conn, user: user} do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -121, :minute)

      conn =
        conn
        |> log_in_user(user, token_authenticated_at: stale_authenticated_at)
        |> put_session(:user_return_to, "/users/settings")
        |> post(~p"/users/log-in", %{
          "_action" => "confirmed",
          "user" => %{"password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."
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
