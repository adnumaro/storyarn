defmodule StoryarnWeb.UserLive.AuthRedirectTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts

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
      {:ok, view, _html} = live(conn, ~p"/users/confirm-access")

      assert has_element?(view, "#confirm-access-vue")
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
