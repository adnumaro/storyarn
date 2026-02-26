defmodule StoryarnWeb.WorkspaceLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Workspace index page" do
    setup :register_and_log_in_user

    test "redirects to default workspace", %{conn: conn} do
      # user_fixture() auto-creates a default workspace during registration
      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/workspaces")

      # Should redirect to the user's default workspace
      assert path =~ ~r"^/workspaces/.+"
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/workspaces")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
