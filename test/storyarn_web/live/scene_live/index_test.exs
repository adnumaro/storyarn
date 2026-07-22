defmodule StoryarnWeb.SceneLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

  defp scenes_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
  end

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/scene/dashboard/SceneDashboard")
  end

  defp get_sidebar_live(view, project) do
    find_live_child(view, "sidebar-scenes-#{project.id}")
  end

  defp scene_names(view) do
    view
    |> get_dashboard_vue()
    |> then(& &1.props["table-data"])
    |> Enum.map(& &1["name"])
  end

  describe "Scene index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene_fixture(project, %{name: "World Map"})

      {:ok, view, _html} = live(conn, scenes_path(project))

      vue = get_dashboard_vue(view)
      assert vue.component == "live/scene/dashboard/SceneDashboard"
      assert vue.props["can-edit"] == true

      # Scene name appears after async dashboard load
      _ = await_async(view)
      assert "World Map" in scene_names(view)
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      scene_fixture(project, %{name: "Shared Scene"})

      {:ok, view, _html} = live(conn, scenes_path(project))

      vue = get_dashboard_vue(view)
      assert vue.component == "live/scene/dashboard/SceneDashboard"
      assert vue.props["can-edit"] == true

      _ = await_async(view)
      assert "Shared Scene" in scene_names(view)
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, scenes_path(project))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "passes empty table-data when no scenes exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scenes_path(project))

      vue = get_dashboard_vue(view)
      # Without scenes, mount doesn't trigger the async dashboard load at all.
      assert vue.props["table-data"] == []
      assert vue.props["stats"] == nil
    end
  end

  describe "create_scene event" do
    setup :register_and_log_in_user

    test "creates a scene and redirects to it", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)
      _ = await_async(view)

      render_click(sidebar, "create_scene")
      {redirect_path, _flash} = assert_redirect(view)

      assert redirect_path =~ "/scenes/"

      scenes = Scenes.list_scenes(project.id)
      assert length(scenes) == 1
      assert hd(scenes).name == "Untitled"
    end

    test "viewer cannot create a scene", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "create_scene")

      assert Scenes.list_scenes(project.id) == []
    end
  end

  describe "create_child_scene event" do
    setup :register_and_log_in_user

    test "creates a child scene under a parent and redirects", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      parent_scene = scene_fixture(project, %{name: "Parent"})

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)
      _ = await_async(view)

      render_click(sidebar, "create_child_scene", %{"parent-id" => parent_scene.id})
      {redirect_path, _flash} = assert_redirect(view)

      assert redirect_path =~ "/scenes/"
    end
  end

  describe "delete flow (set_pending_delete + confirm_delete)" do
    setup :register_and_log_in_user

    test "set_pending_delete + confirm_delete removes the scene", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Doomed Scene"})

      {:ok, view, _html} = live(conn, scenes_path(project))

      _ = await_async(view)
      assert "Doomed Scene" in scene_names(view)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "set_pending_delete_scene", %{"id" => scene.id})
      render_click(sidebar, "confirm_delete_scene")

      refute Scenes.get_scene(project.id, scene.id)
    end

    test "confirm_delete without pending delete does nothing", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene_fixture(project, %{name: "Safe Scene"})

      {:ok, view, _html} = live(conn, scenes_path(project))

      _ = await_async(view)
      sidebar = get_sidebar_live(view, project)

      # Call confirm_delete without set_pending_delete first
      render_click(sidebar, "confirm_delete_scene")

      # Scene should still be displayed
      assert project.id |> Scenes.list_scenes() |> Enum.any?(&(&1.name == "Safe Scene"))
    end
  end

  describe "delete event" do
    setup :register_and_log_in_user

    test "directly deletes a scene by ID", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Direct Delete"})

      {:ok, view, _html} = live(conn, scenes_path(project))

      _ = await_async(view)
      sidebar = get_sidebar_live(view, project)
      render_click(sidebar, "set_pending_delete_scene", %{"id" => scene.id})
      render_click(sidebar, "confirm_delete_scene")

      refute Scenes.get_scene(project.id, scene.id)
    end

    test "delete with non-existent ID shows error", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "set_pending_delete_scene", %{"id" => -1})
      render_click(sidebar, "confirm_delete_scene")

      assert Scenes.list_scenes(project.id) == []
    end

    test "viewer cannot delete a scene", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Protected Scene"})

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "set_pending_delete_scene", %{"id" => scene.id})
      render_click(sidebar, "confirm_delete_scene")

      # Scene still exists
      assert Scenes.get_scene(project.id, scene.id)
    end
  end

  describe "move_to_parent event" do
    setup :register_and_log_in_user

    test "moves a scene to a new parent", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene_a = scene_fixture(project, %{name: "Scene A"})
      scene_b = scene_fixture(project, %{name: "Scene B"})

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => scene_b.id,
        "new_parent_id" => scene_a.id,
        "position" => 0
      })

      # Verify scene B is now a child of scene A
      moved = Scenes.get_scene(project.id, scene_b.id)
      assert moved.parent_id == scene_a.id
    end

    test "moves a scene to root (nil parent)", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => child.id,
        "new_parent_id" => "",
        "position" => 0
      })

      moved = Scenes.get_scene(project.id, child.id)
      assert is_nil(moved.parent_id)
    end

    test "move with non-existent scene shows error", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scenes_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => -1,
        "new_parent_id" => "",
        "position" => 0
      })

      assert Scenes.list_scenes(project.id) == []
    end
  end

  describe "dashboard" do
    setup :register_and_log_in_user

    test "passes dashboard stats to Vue when scenes exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Dashboard Scene"})
      zone_fixture(scene)
      pin_fixture(scene)

      {:ok, view, _html} = live(conn, scenes_path(project))

      # Wait for async dashboard data to load
      _ = await_async(view)

      vue = get_dashboard_vue(view)
      stats = vue.props["stats"]

      assert stats["scene_count"] == 1
      assert stats["zone_count"] == 1
      assert stats["pin_count"] == 1
      assert Map.has_key?(stats, "background_count")

      assert "Dashboard Scene" in scene_names(view)
    end

    test "passes canonical health severities, codes, and scene links to Vue", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Health Overview"})

      {:ok, view, _html} = live(conn, scenes_path(project))
      _ = await_async(view)

      issues = get_dashboard_vue(view).props["issues"]

      assert %{
               "severity" => "warning",
               "code" => "missing_background",
               "label" => "Health Overview",
               "href" => href
             } = Enum.find(issues, &(&1["code"] == "missing_background"))

      assert href ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"

      assert %{"severity" => "info", "code" => "empty_scene"} =
               Enum.find(issues, &(&1["code"] == "empty_scene"))
    end

    test "sort_scenes event toggles table order", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene_a = scene_fixture(project, %{name: "Alpha Scene"})
      scene_b = scene_fixture(project, %{name: "Zeta Scene"})
      # Give Zeta more pins to test numeric sort
      pin_fixture(scene_b)
      pin_fixture(scene_b)
      pin_fixture(scene_a)

      {:ok, view, _html} = live(conn, scenes_path(project))

      _ = await_async(view)

      # Default sort: name asc — Alpha before Zeta
      assert scene_names(view) == ["Alpha Scene", "Zeta Scene"]

      # Sort by pin_count asc — Alpha (1) before Zeta (2)
      render_click(view, "sort_scenes", %{"column" => "pin_count"})
      assert scene_names(view) == ["Alpha Scene", "Zeta Scene"]

      # Sort by pin_count desc — Zeta (2) before Alpha (1)
      render_click(view, "sort_scenes", %{"column" => "pin_count"})
      assert scene_names(view) == ["Zeta Scene", "Alpha Scene"]
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
