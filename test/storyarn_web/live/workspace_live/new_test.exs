defmodule StoryarnWeb.WorkspaceLive.NewTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "New workspace page" do
    setup :register_and_log_in_user

    test "renders the new workspace form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/workspaces/new")

      assert html =~ "Create a new workspace"
      assert html =~ "Workspace name"
    end

    test "shows workspace name and description inputs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      assert has_element?(view, "input[name='workspace[name]']")
      assert has_element?(view, "textarea[name='workspace[description]']")
    end

    test "shows cancel link back to workspaces", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/workspaces/new")

      assert html =~ "Cancel"
      assert html =~ ~r/href="\/workspaces"/
    end

    test "redirects with limit error when workspace limit reached", %{conn: conn} do
      # User already has a default workspace from registration (free plan limit is 1)
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      view
      |> form("form", %{
        "workspace" => %{"name" => "Second Workspace", "description" => "Should be blocked"}
      })
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces"
      assert flash["error"] =~ "workspace limit"
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/workspaces/new")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
