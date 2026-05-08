defmodule StoryarnWeb.WorkspaceLive.NewTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp get_new_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/workspaces/forms/NewWorkspaceForm")
  end

  describe "New workspace page" do
    setup :register_and_log_in_user

    test "renders the new workspace Vue component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      vue = get_new_vue(view)
      assert vue.component == "modules/workspaces/forms/NewWorkspaceForm"
    end

    test "passes form and cancel-url props", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      vue = get_new_vue(view)
      assert is_map(vue.props["form"])
      assert vue.props["cancel-url"] == "/workspaces"
    end

    test "redirects with limit error when workspace limit reached", %{conn: conn} do
      # User already has a default workspace from registration (free plan limit is 1)
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      render_click(view, "save", %{
        "workspace" => %{"name" => "Second Workspace", "description" => "Should be blocked"}
      })

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
