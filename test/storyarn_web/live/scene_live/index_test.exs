defmodule StoryarnWeb.SceneLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Scene index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene_fixture(project, %{name: "World Map"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert html =~ "Scenes"
      assert html =~ "World Map"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      scene_fixture(project, %{name: "Shared Scene"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert html =~ "Scenes"
      assert html =~ "Shared Scene"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders empty state when no scenes exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert html =~ "No scenes yet"
    end
  end

  describe "create_scene event" do
    setup :register_and_log_in_user

    test "creates a scene and redirects to it", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert view
             |> render_click("create_scene")
             |> follow_redirect(conn)

      # The scene was created — verify it exists
      scenes = Storyarn.Scenes.list_scenes(project.id)
      assert length(scenes) == 1
      assert hd(scenes).name == "Untitled"
    end

    test "viewer cannot create a scene", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "create_scene")

      assert render(view) =~ "permission"
    end
  end

  describe "create_child_scene event" do
    setup :register_and_log_in_user

    test "creates a child scene under a parent and redirects", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent_scene = scene_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert view
             |> render_click("create_child_scene", %{"parent-id" => parent_scene.id})
             |> follow_redirect(conn)

      # Verify the child scene was created with proper parent_id
      scenes = Storyarn.Scenes.list_scenes(project.id)
      child = Enum.find(scenes, &(&1.parent_id == parent_scene.id))
      assert child
      assert child.name == "Untitled"
    end
  end

  describe "delete flow (set_pending_delete + confirm_delete)" do
    setup :register_and_log_in_user

    test "set_pending_delete + confirm_delete removes the scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Doomed Scene"})

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      assert html =~ "Doomed Scene"

      render_click(view, "set_pending_delete", %{"id" => scene.id})
      render_click(view, "confirm_delete")

      html = render(view)
      refute html =~ "Doomed Scene"
      assert html =~ "trash"
    end

    test "confirm_delete without pending delete does nothing", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene_fixture(project, %{name: "Safe Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      # Call confirm_delete without set_pending_delete first
      render_click(view, "confirm_delete")

      # Scene should still be displayed
      assert render(view) =~ "Safe Scene"
    end
  end

  describe "delete event" do
    setup :register_and_log_in_user

    test "directly deletes a scene by ID", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Direct Delete"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "delete", %{"id" => scene.id})

      html = render(view)
      refute html =~ "Direct Delete"
    end

    test "delete with non-existent ID shows error", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "delete", %{"id" => -1})

      assert render(view) =~ "not found"
    end

    test "viewer cannot delete a scene", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Protected Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "delete", %{"id" => scene.id})

      assert render(view) =~ "permission"
      # Scene still exists
      assert Storyarn.Scenes.get_scene(project.id, scene.id)
    end
  end

  describe "move_to_parent event" do
    setup :register_and_log_in_user

    test "moves a scene to a new parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene_a = scene_fixture(project, %{name: "Scene A"})
      scene_b = scene_fixture(project, %{name: "Scene B"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "move_to_parent", %{
        "item_id" => scene_b.id,
        "new_parent_id" => scene_a.id,
        "position" => 0
      })

      # Verify scene B is now a child of scene A
      moved = Storyarn.Scenes.get_scene(project.id, scene_b.id)
      assert moved.parent_id == scene_a.id
    end

    test "moves a scene to root (nil parent)", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "move_to_parent", %{
        "item_id" => child.id,
        "new_parent_id" => "",
        "position" => 0
      })

      moved = Storyarn.Scenes.get_scene(project.id, child.id)
      assert is_nil(moved.parent_id)
    end

    test "move with non-existent scene shows error", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      render_click(view, "move_to_parent", %{
        "item_id" => -1,
        "new_parent_id" => "",
        "position" => 0
      })

      assert render(view) =~ "not found"
    end
  end

  describe "switch_tree_tab event" do
    setup :register_and_log_in_user

    test "switches to layers tab", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      # Default is scenes tab
      assert html =~ "tab-active"

      render_click(view, "switch_tree_tab", %{"tab" => "layers"})

      html = render(view)
      assert html =~ "Select a scene to manage layers"
    end

    test "switches back to scenes tab", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene_fixture(project, %{name: "Tab Test Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      # Switch to layers, then back to scenes
      render_click(view, "switch_tree_tab", %{"tab" => "layers"})
      render_click(view, "switch_tree_tab", %{"tab" => "scenes"})

      # Scenes tab content should be visible again
      html = render(view)
      refute html =~ "Select a scene to manage layers"
    end
  end

  describe "handle_info Form.Saved" do
    setup :register_and_log_in_user

    test "redirects to scene show page on Form saved message", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Saved Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      send(view.pid, {StoryarnWeb.SceneLive.Form, {:saved, scene}})

      assert_redirect(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
      )
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/scenes")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
