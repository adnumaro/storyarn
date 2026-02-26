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

    test "validates required name field on empty submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      html =
        view
        |> form("form", %{"workspace" => %{"name" => "", "description" => ""}})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "successfully creates a workspace and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/new")

      view
      |> form("form", %{
        "workspace" => %{"name" => "Test Workspace", "description" => "A workspace for testing"}
      })
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/workspaces/"
      assert flash["info"] =~ "created"
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
