defmodule StoryarnWeb.PageLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.PagesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Pages
  alias Storyarn.Repo

  describe "Page show" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      page = page_fixture(project, %{name: "Test Page"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}"
        )

      assert html =~ "Test Page"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      page = page_fixture(project, %{name: "Shared Page"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}"
        )

      assert html =~ "Shared Page"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      page = page_fixture(project)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end
  end

  describe "move_page event" do
    setup :register_and_log_in_user

    test "moves page to new parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      page1 = page_fixture(project, %{name: "Page 1"})
      page2 = page_fixture(project, %{name: "Page 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page1.id}"
        )

      # Simulate move_page event
      render_hook(view, "move_page", %{
        "page_id" => page2.id,
        "parent_id" => page1.id,
        "position" => 0
      })

      # Verify page was moved
      updated_page = Pages.get_page(project.id, page2.id)
      assert updated_page.parent_id == page1.id
    end

    test "moves page to root level", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = page_fixture(project, %{name: "Parent"})
      child = page_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{child.id}"
        )

      # Move to root level (empty parent_id)
      render_hook(view, "move_page", %{
        "page_id" => child.id,
        "parent_id" => "",
        "position" => 0
      })

      # Verify page was moved to root
      updated_page = Pages.get_page(project.id, child.id)
      assert updated_page.parent_id == nil
    end

    test "prevents cycle creation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = page_fixture(project, %{name: "Parent"})
      child = page_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{parent.id}"
        )

      # Try to move parent under its child (would create cycle)
      render_hook(view, "move_page", %{
        "page_id" => parent.id,
        "parent_id" => child.id,
        "position" => 0
      })

      # Verify page was NOT moved
      updated_page = Pages.get_page(project.id, parent.id)
      assert updated_page.parent_id == nil
    end

    test "viewer cannot move pages", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      page1 = page_fixture(project, %{name: "Page 1"})
      page2 = page_fixture(project, %{name: "Page 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page1.id}"
        )

      # Try to move page
      render_hook(view, "move_page", %{
        "page_id" => page2.id,
        "parent_id" => page1.id,
        "position" => 0
      })

      # Verify page was NOT moved
      updated_page = Pages.get_page(project.id, page2.id)
      assert updated_page.parent_id == nil
    end
  end

  describe "create_child_page event" do
    setup :register_and_log_in_user

    test "creates child page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = page_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{parent.id}"
        )

      # Get initial page count
      initial_tree = Pages.list_pages_tree(project.id)
      initial_count = count_pages(initial_tree)

      # Create child page
      render_hook(view, "create_child_page", %{"parent-id" => parent.id})

      # Verify new page was created
      updated_tree = Pages.list_pages_tree(project.id)
      assert count_pages(updated_tree) == initial_count + 1

      # Verify it's a child of parent
      parent_page = Pages.get_page_with_descendants(project.id, parent.id)
      assert length(parent_page.children) == 1
    end

    test "viewer cannot create child pages", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      parent = page_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{parent.id}"
        )

      # Get initial page count
      initial_tree = Pages.list_pages_tree(project.id)
      initial_count = count_pages(initial_tree)

      # Try to create child page
      render_hook(view, "create_child_page", %{"parent-id" => parent.id})

      # Verify page was NOT created
      updated_tree = Pages.list_pages_tree(project.id)
      assert count_pages(updated_tree) == initial_count
    end
  end

  defp count_pages(pages) when is_list(pages) do
    Enum.reduce(pages, 0, fn page, acc ->
      acc + 1 + count_pages(Map.get(page, :children, []))
    end)
  end
end
