defmodule StoryarnWeb.SceneLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias StoryarnWeb.SceneLive.Helpers.SceneHelpers
  alias StoryarnWeb.SceneLive.Index

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
      _ = await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.props["table-data"] == []
      assert vue.props["stats"]["scene_count"] == 0
      assert vue.props["overview-status"] == "ready"
      assert vue.props["issues-status"] == "ready"
      assert vue.props["issue-pagination"]["total"] == 0
    end

    test "refreshes the visible dashboard after a committed scene update", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Before"})

      {:ok, view, _html} = live(conn, scenes_path(project))
      await_async(view)
      assert "Before" in scene_names(view)

      assert {:ok, _scene} = Scenes.update_scene(scene, %{name: "After"})

      assert_dashboard_eventually(view, fn ->
        assert "After" in scene_names(view)
        refute "Before" in scene_names(view)
      end)
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

      assert %{"href" => href} =
               Enum.find(vue.props["table-data"], &(&1["id"] == scene.id))

      assert href ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
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
               "id" => id,
               "severity" => "warning",
               "code" => "missing_background",
               "label" => "Health Overview",
               "scene_id" => scene_id,
               "entity_type" => "scene",
               "entity_id" => nil,
               "resource_id" => resource_id,
               "resource_label" => "Health Overview",
               "href" => href
             } = Enum.find(issues, &(&1["code"] == "missing_background"))

      assert is_binary(id)
      assert scene_id == scene.id
      assert resource_id == scene.id

      assert href ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"

      assert %{"severity" => "info", "code" => "empty_scene"} =
               Enum.find(issues, &(&1["code"] == "empty_scene"))
    end

    test "names a scene the author never named the way the editor does", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Temporary"})
      # A name the changeset would refuse but the column accepts, which is what a
      # blank name looks like once it is in the database.
      Repo.update_all(from(s in Scene, where: s.id == ^scene.id), set: [name: "   "])

      {:ok, view, _html} = live(conn, scenes_path(project))
      _ = await_async(view)

      issue = Enum.find(get_dashboard_vue(view).props["issues"], &(&1["code"] == "missing_background"))

      # The editor popover falls back to the scene word; a dashboard row that
      # rendered the raw blank would name the same scene differently.
      assert issue["label"] == SceneHelpers.element_type_label("scene")
    end

    test "assigns unique stable IDs when one entity emits the same code twice", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Duplicate Findings"})

      zone =
        zone_fixture(scene, %{
          "name" => "Double Reference",
          "action_type" => "display",
          "is_walkable" => false,
          "action_data" => %{
            "variable_ref" => "hero.missing",
            "display_mode" => "value"
          },
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{
                "id" => "block-1",
                "type" => "block",
                "logic" => "all",
                "rules" => [
                  %{
                    "id" => "rule-1",
                    "sheet" => "hero",
                    "variable" => "missing",
                    "operator" => "equals",
                    "value" => "x"
                  }
                ]
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, scenes_path(project))
      _ = await_async(view)

      [first_issue, survivor_issue] = stale_variable_issues(view, zone.id)
      stable_ids = Enum.map([first_issue, survivor_issue], & &1["id"])
      assert length(stable_ids) == 2
      assert length(Enum.uniq(stable_ids)) == 2

      DashboardCache.invalidate(project.id)
      send(view.pid, :load_dashboard_data)
      _ = await_async(view)

      assert Enum.map(stale_variable_issues(view, zone.id), & &1["id"]) == stable_ids

      removal_attrs =
        case first_issue["details"] do
          %{"reference" => _reference} ->
            %{
              "action_data" => %{
                "variable_ref" => "",
                "display_mode" => "value"
              }
            }

          %{"references" => _references} ->
            %{"condition" => nil}
        end

      assert {:ok, _updated_zone} = Scenes.update_zone(zone, removal_attrs)

      DashboardCache.invalidate(project.id)
      send(view.pid, :load_dashboard_data)
      _ = await_async(view)

      assert [remaining_issue] = stale_variable_issues(view, zone.id)
      assert remaining_issue["id"] == survivor_issue["id"]
    end

    test "paginates and filters issues while preserving controls across refresh", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      scenes =
        for index <- 1..26 do
          scene_fixture(project, %{name: "Scene #{String.pad_leading(to_string(index), 2, "0")}"})
        end

      {:ok, view, _html} = live(conn, scenes_path(project))
      _ = await_async(view)

      initial = get_dashboard_vue(view).props
      assert length(initial["table-data"]) == 25
      assert initial["pagination"]["page"] == 1
      assert initial["pagination"]["total"] == 26
      assert initial["pagination"]["totalPages"] == 2
      assert length(initial["issues"]) == 25
      assert initial["issue-pagination"]["page"] == 1
      assert initial["issue-pagination"]["unfilteredTotal"] == 52

      assert initial["issue-filter-options"]["totals"] == %{
               "severity" => 52,
               "code" => 52,
               "resource" => 52
             }

      assert initial["issue-filter-options"]["severities"] == [
               %{"value" => "error", "count" => 0},
               %{"value" => "warning", "count" => 26},
               %{"value" => "info", "count" => 26}
             ]

      assert initial["issue-filter-options"]["codes"] == [
               %{"value" => "empty_scene", "count" => 26},
               %{"value" => "missing_background", "count" => 26}
             ]

      assert length(initial["issue-filter-options"]["resources"]) == 26
      assert Enum.all?(initial["issue-filter-options"]["resources"], &(&1["count"] == 2))

      render_click(view, "page_scenes", %{"page" => 2})
      assert length(get_dashboard_vue(view).props["table-data"]) == 1

      render_click(view, "filter_scene_issues", %{
        "filter" => "code",
        "value" => "missing_background"
      })

      filtered = get_dashboard_vue(view).props
      assert filtered["issue-filters"]["code"] == "missing_background"
      assert filtered["issue-pagination"]["page"] == 1
      assert filtered["issue-pagination"]["total"] == 26
      assert filtered["issue-pagination"]["totalPages"] == 2
      assert Enum.all?(filtered["issues"], &(&1["code"] == "missing_background"))

      assert filtered["issue-filter-options"]["totals"] == %{
               "severity" => 26,
               "code" => 52,
               "resource" => 26
             }

      assert filtered["issue-filter-options"]["severities"] == [
               %{"value" => "error", "count" => 0},
               %{"value" => "warning", "count" => 26},
               %{"value" => "info", "count" => 0}
             ]

      assert Enum.all?(filtered["issue-filter-options"]["resources"], &(&1["count"] == 1))

      render_click(view, "page_scene_issues", %{"page" => 2})

      second_page = get_dashboard_vue(view).props
      assert second_page["issue-pagination"]["page"] == 2
      assert length(second_page["issues"]) == 1

      send(view.pid, :load_dashboard_data)
      _ = await_async(view)

      refreshed = get_dashboard_vue(view).props
      assert refreshed["pagination"]["page"] == 2
      assert length(refreshed["table-data"]) == 1
      assert refreshed["issue-filters"]["code"] == "missing_background"
      assert refreshed["issue-pagination"]["page"] == 2
      assert length(refreshed["issues"]) == 1
      assert refreshed["issue-filter-options"] == filtered["issue-filter-options"]

      selected_scene = hd(scenes)

      render_click(view, "filter_scene_issues", %{
        "filter" => "resource",
        "value" => to_string(selected_scene.id)
      })

      resource_filtered = get_dashboard_vue(view).props
      assert resource_filtered["issue-pagination"]["page"] == 1
      assert resource_filtered["issue-pagination"]["total"] == 1
      assert resource_filtered["issue-filter-options"]["totals"]["severity"] == 1
      assert resource_filtered["issue-filter-options"]["totals"]["code"] == 2
      assert resource_filtered["issue-filter-options"]["totals"]["resource"] == 26

      assert [%{"resource_id" => resource_id, "id" => issue_id}] =
               resource_filtered["issues"]

      assert resource_id == selected_scene.id
      assert is_binary(issue_id)
    end

    test "a crashed overview load surfaces instead of hanging on the skeleton", %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: project,
          dashboard_stats: nil,
          overview_status: :loading,
          flash: %{}
        }
      }

      {:noreply, result} =
        Index.handle_async(:load_dashboard_overview, {:exit, :boom}, socket)

      assert result.assigns.dashboard_stats == nil
      assert result.assigns.overview_status == :error
    end

    test "a crashed initial issues load exposes its independent error state", %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: project,
          issues_status: :loading,
          flash: %{}
        }
      }

      {:noreply, result} =
        Index.handle_async(:load_dashboard_issues, {:exit, :boom}, socket)

      assert result.assigns.issues_status == :error
    end

    test "and the overview failure reason reaches the log rather than being swallowed", %{
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: project,
          dashboard_stats: nil,
          overview_status: :loading,
          flash: %{}
        }
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Index.handle_async(:load_dashboard_overview, {:exit, {:badarg, []}}, socket)
        end)

      assert log =~ "Scene dashboard overview load failed for project #{project.id}"
      assert log =~ "badarg"
    end

    test "retry immediately returns the overview to loading" do
      socket = %Socket{assigns: %{__changed__: %{}, overview_status: :error}}

      {:noreply, result} = Index.handle_event("retry_dashboard_overview", %{}, socket)

      assert result.assigns.overview_status == :loading
      assert_receive :load_dashboard_overview
      refute_receive :load_dashboard_issues
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

  defp stale_variable_issues(view, zone_id) do
    view
    |> get_dashboard_vue()
    |> then(& &1.props["issues"])
    |> Enum.filter(&(&1["code"] == "stale_variable_reference" and &1["entity_id"] == zone_id))
  end

  defp assert_dashboard_eventually(view, assertion, attempts \\ 200)

  defp assert_dashboard_eventually(view, assertion, attempts) when attempts > 1 do
    render(view)
    await_async(view)
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      assert_dashboard_eventually(view, assertion, attempts - 1)
  end

  defp assert_dashboard_eventually(view, assertion, 1) do
    render(view)
    await_async(view)
    assertion.()
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
