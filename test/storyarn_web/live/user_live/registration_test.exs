defmodule StoryarnWeb.UserLive.RegistrationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  describe "Registration page (beta lockdown)" do
    test "redirects unauthenticated users to landing", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/register")
    end

    test "redirects authenticated users to signed-in path", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")

      assert {:error, {:redirect, _}} = result
    end
  end
end
