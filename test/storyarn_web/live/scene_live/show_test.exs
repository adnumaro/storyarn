defmodule StoryarnWeb.SceneLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures, only: [flow_fixture: 1]
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Versioning

  # Reads the SceneCanvas Vue component and builds a composite scene_data map
  # whose keys match the V1 data-scene JSON shape (snake_case). This keeps all
  # existing test assertions valid while sourcing the data from V2 Vue props.
  defp extract_scene_data(view) do
    vue = get_scene_canvas_vue(view)
    scene = vue.props["scene-data"] || %{}

    scene
    |> snake_keys()
    |> Map.merge(%{
      "pins" => Enum.map(vue.props["pins"] || [], &snake_keys/1),
      "zones" => Enum.map(vue.props["zones"] || [], &snake_keys/1),
      "connections" => Enum.map(vue.props["connections"] || [], &snake_keys/1),
      "annotations" => Enum.map(vue.props["annotations"] || [], &snake_keys/1),
      "layers" => Enum.map(vue.props["layers"] || [], &snake_keys/1)
    })
  end

  defp get_scene_header_props(view) do
    view
    |> LiveVue.Test.get_vue(name: "live/scene/show/SceneHeader")
    |> then(& &1.props["header"])
  end

  defp get_scene_surface_props(view) do
    view
    |> LiveVue.Test.get_vue(name: "live/scene/show/SceneSurface")
    |> then(& &1.props["surface"])
  end

  defp get_scene_panels_props(view) do
    view
    |> LiveVue.Test.get_vue(name: "live/scene/show/ScenePanels")
    |> then(& &1.props["panels"])
  end

  defp get_scene_canvas_vue(view) do
    canvas = get_scene_surface_props(view)["canvas"]

    %{
      component: "modules/scenes/editor/components/canvas/SceneCanvas",
      id: canvas["id"],
      props: %{
        "scene-data" => canvas["sceneData"],
        "pins" => canvas["pins"],
        "zones" => canvas["zones"],
        "connections" => canvas["connections"],
        "annotations" => canvas["annotations"],
        "layers" => canvas["layers"],
        "active-tool" => canvas["activeTool"],
        "edit-mode" => canvas["editMode"],
        "can-edit" => canvas["canEdit"],
        "collaboration" => canvas["collaboration"]
      }
    }
  end

  defp get_scene_dock_vue(view) do
    dock = get_scene_surface_props(view)["dock"]

    %{
      component: "modules/scenes/editor/components/chrome/dock/SceneDock",
      props: %{
        "active-tool" => dock["activeTool"],
        "edit-mode" => dock["editMode"],
        "compact" => dock["compact"],
        "pending-sheet" => dock["pendingSheet"],
        "project-sheets" => dock["projectSheets"],
        "workspace-slug" => dock["workspaceSlug"],
        "project-slug" => dock["projectSlug"],
        "scene-id" => dock["sceneId"]
      }
    }
  end

  defp get_element_panel_vue(view) do
    panel = get_scene_panels_props(view)["element"]

    %{
      component: "modules/scenes/editor/components/panels/ElementPropertiesPanel",
      props: %{
        "selected-type" => panel["selectedType"],
        "selected-element" => panel["selectedElement"],
        "can-edit" => panel["canEdit"],
        "element-panel-open" => panel["elementPanelOpen"],
        "project-sheets" => panel["projectSheets"],
        "project-flows" => panel["projectFlows"],
        "project-scenes" => panel["projectScenes"],
        "project-variables" => panel["projectVariables"]
      }
    }
  end

  defp get_search_panel_vue(view) do
    search = get_scene_header_props(view)["search"]

    %{
      component: "modules/scenes/editor/components/chrome/header/SearchPanel",
      props: %{
        "search-query" => search["searchQuery"],
        "search-filter" => search["searchFilter"],
        "search-results" => search["searchResults"]
      }
    }
  end

  defp get_layer_list_props(view) do
    layers = get_scene_surface_props(view)["layers"]

    %{
      "layers" => layers["layers"],
      "active-layer-id" => layers["activeLayerId"],
      "can-edit" => layers["canEdit"],
      "edit-mode" => layers["editMode"],
      "popover-open" => layers["popoverOpen"]
    }
  end

  defp get_legend_vue(view) do
    legend = get_scene_surface_props(view)["legend"]

    %{
      component: "modules/scenes/editor/components/chrome/layers/Legend",
      props: %{
        "legend-data" => legend["legendData"],
        "legend-open" => legend["legendOpen"]
      }
    }
  end

  defp search_result_ids(view, type) do
    view
    |> get_search_panel_vue()
    |> then(& &1.props["search-results"])
    |> Enum.filter(&(&1["type"] == type))
    |> Enum.map(& &1["id"])
  end

  # Recursively converts camelCase string map keys into snake_case.
  defp snake_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_snake(k), snake_keys(v)} end)
  end

  defp snake_keys(list) when is_list(list), do: Enum.map(list, &snake_keys/1)
  defp snake_keys(other), do: other

  defp to_snake(key) when is_binary(key) do
    key
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  defp to_snake(key), do: key

  describe "canvas rendering" do
    setup :register_and_log_in_user

    test "mounts the SceneCanvas Vue component", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "World Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vue = get_scene_canvas_vue(view)
      assert vue.component == "modules/scenes/editor/components/canvas/SceneCanvas"
      assert vue.id == "scene-canvas-#{scene.id}"
    end

    test "compact layout mounts the public compact surface boundary", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Compact Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}?layout=compact"
        )

      vue = LiveVue.Test.get_vue(view, name: "live/scene/show/SceneCompactSurface")
      assert vue.component == "live/scene/show/SceneCompactSurface"
      assert vue.id == "scene-compact-surface-#{scene.id}"
      assert vue.props["surface"]["canvas"]["sceneData"]["name"] == "Compact Scene"
      assert vue.props["surface"]["canvas"]["id"] == "scene-canvas-compact-#{scene.id}"
      assert vue.props["surface"]["dock"]["sceneId"] == scene.id
      assert vue.props["surface"]["dock"]["compact"] == true
      assert vue.props["surface"]["dock"]["editMode"] == true
    end

    test "data-scene contains valid JSON with scene fields", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Test Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      assert scene_data["id"] == scene.id
      assert scene_data["name"] == "Test Scene"
      assert is_number(scene_data["default_zoom"])
      assert is_number(scene_data["default_center_x"])
      assert is_number(scene_data["default_center_y"])
    end

    test "includes background URL when background_asset_id is set",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/bg.png"})

      scene = scene_fixture(project, %{name: "BG Scene"})
      {:ok, _scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      assert scene_data["background_url"] == "https://example.com/bg.png"
    end

    test "renders without error when no background asset", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "No BG Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      assert is_nil(scene_data["background_url"])
    end

    test "SceneToolbar shows the scene name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "My Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      toolbar = get_scene_header_props(view)["toolbar"]
      assert toolbar["sceneName"] == "My Scene"
    end

    test "SceneToolbar exposes the scene shortcut", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Test Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      toolbar = get_scene_header_props(view)["toolbar"]
      assert toolbar["sceneShortcut"] == scene.shortcut
    end
  end

  describe "save_name event" do
    setup :register_and_log_in_user

    test "updates scene name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Original"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "save_name", %{"name" => "Updated Name"})

      updated = Scenes.get_scene(project.id, scene.id)
      assert updated.name == "Updated Name"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Original"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "save_name", %{"name" => "Hacked"})

      unchanged = Scenes.get_scene(project.id, scene.id)
      assert unchanged.name == "Original"
    end
  end

  describe "access control" do
    setup :register_and_log_in_user

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders for viewer member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Viewable Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vue = get_scene_canvas_vue(view)
      assert vue.component == "modules/scenes/editor/components/canvas/SceneCanvas"
      assert vue.props["scene-data"]["name"] == "Viewable Scene"
      assert vue.props["can-edit"] == false
    end

    test "viewer element panel exposes can-edit false even for unlocked elements", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Viewable Scene"})
      zone = zone_fixture(scene, %{"name" => "Unlocked Zone", "locked" => false})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == "zone"
      assert panel.props["can-edit"] == false
    end
  end

  describe "dock and tools" do
    setup :register_and_log_in_user

    test "renders dock for editor in edit mode", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      dock = get_scene_dock_vue(view)
      assert dock.props["edit-mode"] == true
      assert dock.props["active-tool"] == "select"
    end

    test "does not render dock for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      refute html =~ "scene-dock"
      refute html =~ "set_tool"
    end

    test "set_tool updates active tool", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_tool", %{"type" => "pin"})

      canvas = get_scene_canvas_vue(view)
      assert canvas.props["active-tool"] == "pin"
    end

    test "renders SceneActions toolbar for editor", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      actions = LiveVue.Test.get_vue(view, name: "live/scene/show/SceneHeaderActions")
      assert actions.props["can-edit"] == true
      assert actions.props["edit-mode"] == true
    end

    test "toggle_edit_mode switches to view mode", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Default is edit mode for editors — dock should be visible in surface props
      assert get_scene_dock_vue(view).props["edit-mode"] == true

      # Toggle to view mode — dock should disappear
      render_click(view, "toggle_edit_mode", %{})
      assert get_scene_dock_vue(view).props["edit-mode"] == false

      # Toggle back to edit mode — dock returns
      render_click(view, "toggle_edit_mode", %{})
      assert get_scene_dock_vue(view).props["edit-mode"] == true
    end

    test "viewer cannot toggle to edit mode", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "toggle_edit_mode", %{})
      assert html =~ "permission"
    end
  end

  describe "create_pin event" do
    setup :register_and_log_in_user

    test "creates pin with valid coordinates", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_pin", %{"position_x" => 30.5, "position_y" => 60.0})

      pins = Scenes.list_pins(scene.id)
      assert length(pins) == 1
      [pin] = pins
      assert_in_delta pin.position_x, 30.5, 0.01
      assert_in_delta pin.position_y, 60.0, 0.01
      assert pin.label == "New Pin"
      assert pin.pin_type == "location"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_pin", %{"position_x" => 50.0, "position_y" => 50.0})

      pins = Scenes.list_pins(scene.id)
      assert pins == []
    end
  end

  describe "move_pin event" do
    setup :register_and_log_in_user

    test "updates pin coordinates", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"position_x" => 10.0, "position_y" => 20.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      updated = Scenes.get_pin!(pin.id)
      assert_in_delta updated.position_x, 80.0, 0.01
      assert_in_delta updated.position_y, 90.0, 0.01
    end
  end

  describe "select_element and deselect events" do
    setup :register_and_log_in_user

    test "select_element assigns selected pin", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      # Verify assigns via a re-render — the deselect clears them
      render_hook(view, "deselect", %{})
    end
  end

  describe "dock zone tools" do
    setup :register_and_log_in_user

    test "set_tool accepts zone-drawing tools", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      for tool <- ~w(freeform rectangle triangle circle) do
        render_click(view, "set_tool", %{"type" => tool})
        canvas = get_scene_canvas_vue(view)
        assert canvas.props["active-tool"] == tool
      end
    end

    test "set_tool freeform activates freeform", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_tool", %{"type" => "freeform"})

      canvas = get_scene_canvas_vue(view)
      assert canvas.props["active-tool"] == "freeform"
    end
  end

  describe "create_zone event" do
    setup :register_and_log_in_user

    test "creates zone with 3+ valid vertices", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"name" => "Test Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert zone.name == "Test Zone"
      assert length(zone.vertices) == 3
    end

    test "uses default name when empty", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"name" => "", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert zone.name == "New Zone"
    end

    test "rejects zone with fewer than 3 vertices", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0}
      ]

      html = render_hook(view, "create_zone", %{"name" => "Bad Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert zones == []
      assert html =~ "Invalid zone"
    end

    test "accepts zones with out-of-canvas coordinates", %{conn: conn, user: user} do
      # V2 removed the 0-100 clamp: elements may live outside the canvas.
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vertices = [
        %{"x" => -10.0, "y" => 10.0},
        %{"x" => 150.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"name" => "Off-canvas Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert zone.name == "Off-canvas Zone"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"name" => "Hack Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert zones == []
    end

    test "creates zone with rectangle preset vertices (4 vertices)", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Rectangle centered at (50, 50): 20x15 units
      vertices = [
        %{"x" => 40.0, "y" => 42.5},
        %{"x" => 60.0, "y" => 42.5},
        %{"x" => 60.0, "y" => 57.5},
        %{"x" => 40.0, "y" => 57.5}
      ]

      render_hook(view, "create_zone", %{"name" => "", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert length(zone.vertices) == 4

      Enum.each(zone.vertices, fn v ->
        assert v["x"] >= 0 and v["x"] <= 100
        assert v["y"] >= 0 and v["y"] <= 100
      end)
    end

    test "creates zone with triangle preset vertices (3 vertices)", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Triangle centered at (50, 50)
      vertices = [
        %{"x" => 50.0, "y" => 41.5},
        %{"x" => 60.0, "y" => 58.5},
        %{"x" => 40.0, "y" => 58.5}
      ]

      render_hook(view, "create_zone", %{"name" => "", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert length(zone.vertices) == 3
    end

    test "creates zone with circle preset vertices (16 vertices)", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Circle centered at (50, 50), 16-sided polygon, radius 10
      vertices =
        Enum.map(0..15, fn i ->
          angle = i / 16 * 2 * :math.pi() - :math.pi() / 2

          %{
            "x" => Float.round(50.0 + 10 * :math.cos(angle), 2),
            "y" => Float.round(50.0 + 10 * :math.sin(angle), 2)
          }
        end)

      render_hook(view, "create_zone", %{"name" => "", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert length(zone.vertices) == 16

      Enum.each(zone.vertices, fn v ->
        assert v["x"] >= 0 and v["x"] <= 100
        assert v["y"] >= 0 and v["y"] <= 100
      end)
    end
  end

  describe "scene_data serialization" do
    setup :register_and_log_in_user

    test "includes pins in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{"label" => "Test Pin", "position_x" => 25.0, "position_y" => 75.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      assert length(scene_data["pins"]) == 1
      [pin_data] = scene_data["pins"]
      assert pin_data["label"] == "Test Pin"
      assert pin_data["position_x"] == 25.0
      assert pin_data["position_y"] == 75.0
    end

    test "includes zones in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone = zone_fixture(scene, %{"name" => "Test Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      assert length(scene_data["zones"]) == 1
      [zone_data] = scene_data["zones"]
      assert zone_data["name"] == "Test Zone"
      assert is_list(zone_data["vertices"])
      assert length(zone_data["vertices"]) == 3
    end

    test "includes connections in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A", "position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(scene, %{"label" => "B", "position_x" => 90.0, "position_y" => 90.0})
      _conn_record = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      assert length(scene_data["connections"]) == 1
      [conn_data] = scene_data["connections"]
      assert conn_data["from_pin_id"] == pin1.id
      assert conn_data["to_pin_id"] == pin2.id
    end

    test "includes layers in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      # Scene always has at least 1 default layer
      assert scene_data["layers"] != []
      [layer_data | _] = scene_data["layers"]
      assert is_binary(layer_data["name"])
      assert is_boolean(layer_data["visible"])
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4: Selection + Properties Panel
  # ---------------------------------------------------------------------------

  describe "select_element with properties panel" do
    setup :register_and_log_in_user

    test "selecting a pin exposes pin data via ElementPropertiesPanel", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == "pin"
      assert panel.props["selected-element"]["label"] == "Castle"
    end

    test "selecting a zone exposes zone data via ElementPropertiesPanel", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Dark Forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == "zone"
      assert panel.props["selected-element"]["name"] == "Dark Forest"
    end

    test "deselect clears the ElementPropertiesPanel selection", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})
      render_hook(view, "deselect", %{})

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == nil
      assert panel.props["selected-element"] == nil
    end
  end

  describe "update_pin event" do
    setup :register_and_log_in_user

    test "updates pin label", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Old Label"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "label",
        "value" => "New Label"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.label == "New Label"
    end

    test "updates pin color", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "color",
        "value" => "#ff0000"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.color == "#ff0000"
    end

    test "updates pin type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"pin_type" => "location"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "pin_type",
        "value" => "character"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.pin_type == "character"
    end

    test "syncs previous party leader when assigning a new leader", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      previous_leader =
        pin_fixture(scene, %{
          "label" => "Previous Leader",
          "is_playable" => true,
          "is_leader" => true
        })

      new_leader =
        pin_fixture(scene, %{
          "label" => "New Leader",
          "is_playable" => true,
          "is_leader" => false
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(new_leader.id),
        "field" => "is_leader",
        "toggle" => "true"
      })

      refute Scenes.get_pin!(previous_leader.id).is_leader
      assert Scenes.get_pin!(new_leader.id).is_leader

      scene_data = extract_scene_data(view)
      previous_leader_data = Enum.find(scene_data["pins"], &(&1["id"] == previous_leader.id))
      new_leader_data = Enum.find(scene_data["pins"], &(&1["id"] == new_leader.id))

      assert previous_leader_data["is_leader"] == false
      assert new_leader_data["is_leader"] == true
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Original"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "label",
        "value" => "Hacked"
      })

      unchanged = Scenes.get_pin!(pin.id)
      assert unchanged.label == "Original"
    end
  end

  describe "update_zone event" do
    setup :register_and_log_in_user

    test "updates zone name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Old Name"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "name",
        "value" => "New Name"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.name == "New Name"
    end

    test "updates zone fill_color", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "fill_color",
        "value" => "#00ff00"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.fill_color == "#00ff00"
    end

    test "updates zone opacity", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "opacity",
        "value" => "0.5"
      })

      updated = Scenes.get_zone!(zone.id)
      assert_in_delta updated.opacity, 0.5, 0.01
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Original"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "name",
        "value" => "Hacked"
      })

      unchanged = Scenes.get_zone!(zone.id)
      assert unchanged.name == "Original"
    end
  end

  describe "upload_zone_label_icon event" do
    setup :register_and_log_in_user

    test "stores a valid SVG icon on the zone", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><circle cx="4" cy="4" r="3"/></svg>)

      render_hook(view, "upload_zone_label_icon", %{
        "id" => to_string(zone.id),
        "filename" => "icon.svg",
        "content_type" => "image/svg+xml",
        "data" => "data:image/svg+xml;base64,#{Base.encode64(svg)}"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.label_icon_asset_id
    end

    test "rejects files whose binary does not match the declared icon type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      render_hook(view, "upload_zone_label_icon", %{
        "id" => to_string(zone.id),
        "filename" => "icon.png",
        "content_type" => "image/png",
        "data" => "data:image/png;base64,#{Base.encode64("not a png")}"
      })

      updated = Scenes.get_zone!(zone.id)
      assert is_nil(updated.label_icon_asset_id)
    end

    test "rejects transparent-hostile image extensions", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      render_hook(view, "upload_zone_label_icon", %{
        "id" => to_string(zone.id),
        "filename" => "icon.jpg",
        "content_type" => "image/jpeg",
        "data" => "data:image/jpeg;base64,#{Base.encode64(<<255, 216, 255, 217>>)}"
      })

      updated = Scenes.get_zone!(zone.id)
      assert is_nil(updated.label_icon_asset_id)
    end
  end

  describe "upload_pin_icon event" do
    setup :register_and_log_in_user

    test "stores a valid SVG icon on the pin", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><circle cx="4" cy="4" r="3"/></svg>)

      render_hook(view, "upload_pin_icon", %{
        "id" => to_string(pin.id),
        "filename" => "pin.svg",
        "content_type" => "image/svg+xml",
        "data" => "data:image/svg+xml;base64,#{Base.encode64(svg)}"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.icon_asset_id
    end

    test "rejects files whose binary does not match the declared pin icon type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      render_hook(view, "upload_pin_icon", %{
        "id" => to_string(pin.id),
        "filename" => "pin.png",
        "content_type" => "image/png",
        "data" => "data:image/png;base64,#{Base.encode64("not a png")}"
      })

      updated = Scenes.get_pin!(pin.id)
      assert is_nil(updated.icon_asset_id)
    end

    test "rejects transparent-hostile pin icon extensions", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")

      render_hook(view, "upload_pin_icon", %{
        "id" => to_string(pin.id),
        "filename" => "pin.jpg",
        "content_type" => "image/jpeg",
        "data" => "data:image/jpeg;base64,#{Base.encode64(<<255, 216, 255, 217>>)}"
      })

      updated = Scenes.get_pin!(pin.id)
      assert is_nil(updated.icon_asset_id)
    end
  end

  describe "delete element from panel" do
    setup :register_and_log_in_user

    test "delete_pin removes pin and clears selection", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Doomed Pin"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select pin first
      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      # Delete via confirm flow
      render_hook(view, "set_pending_delete_pin", %{"id" => to_string(pin.id)})
      html = render_hook(view, "confirm_delete_element", %{})

      # Panel should be gone
      refute html =~ "properties-panel"

      # Pin should be deleted from DB
      assert Scenes.get_pin(pin.id) == nil
    end

    test "delete_zone removes zone and clears selection", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Doomed Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select zone first
      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})

      # Delete via confirm flow
      render_hook(view, "set_pending_delete_zone", %{"id" => to_string(zone.id)})
      html = render_hook(view, "confirm_delete_element", %{})

      # Panel should be gone
      refute html =~ "properties-panel"

      # Zone should be deleted from DB
      assert Scenes.get_zone(zone.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Task 5: Connection Drawing + Rendering
  # ---------------------------------------------------------------------------

  describe "connector tool" do
    setup :register_and_log_in_user

    test "set_tool connector is a valid tool", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_tool", %{"type" => "connector"})
      canvas = get_scene_canvas_vue(view)
      assert canvas.props["active-tool"] == "connector"
    end

    test "set_tool connector activates connector", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_tool", %{"type" => "connector"})
      canvas = get_scene_canvas_vue(view)
      assert canvas.props["active-tool"] == "connector"
    end
  end

  describe "create_connection event" do
    setup :register_and_log_in_user

    test "creates connection between two valid pins", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A", "position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(scene, %{"label" => "B", "position_x" => 90.0, "position_y" => 90.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_connection", %{
        "from_pin_id" => pin1.id,
        "to_pin_id" => pin2.id
      })

      conns = Scenes.list_connections(scene.id)
      assert length(conns) == 1
      [connection] = conns
      assert connection.from_pin_id == pin1.id
      assert connection.to_pin_id == pin2.id
    end

    test "rejects connection from pin to itself", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Self"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_hook(view, "create_connection", %{
          "from_pin_id" => pin.id,
          "to_pin_id" => pin.id
        })

      conns = Scenes.list_connections(scene.id)
      assert conns == []
      assert html =~ "Could not create connection"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_connection", %{
        "from_pin_id" => pin1.id,
        "to_pin_id" => pin2.id
      })

      conns = Scenes.list_connections(scene.id)
      assert conns == []
    end
  end

  describe "update_connection event" do
    setup :register_and_log_in_user

    test "updates connection label", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_connection", %{
        "id" => to_string(connection.id),
        "field" => "label",
        "value" => "Trade Route"
      })

      updated = Scenes.get_connection!(scene.id, connection.id)
      assert updated.label == "Trade Route"
    end

    test "updates connection line_style", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_connection", %{
        "id" => to_string(connection.id),
        "field" => "line_style",
        "value" => "dashed"
      })

      updated = Scenes.get_connection!(scene.id, connection.id)
      assert updated.line_style == "dashed"
    end

    test "updates connection bidirectional flag", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_connection", %{
        "id" => to_string(connection.id),
        "field" => "bidirectional",
        "toggle" => "false"
      })

      updated = Scenes.get_connection!(scene.id, connection.id)
      assert updated.bidirectional == false
    end
  end

  describe "select and delete connection" do
    setup :register_and_log_in_user

    test "selecting a connection shows connection properties panel", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{
        "type" => "connection",
        "id" => connection.id
      })

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == "connection"
      assert panel.props["selected-element"]["id"] == connection.id
    end

    test "delete_connection removes and clears selection", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "connection", "id" => connection.id})
      render_hook(view, "set_pending_delete_connection", %{"id" => to_string(connection.id)})
      html = render_hook(view, "confirm_delete_element", %{})

      refute html =~ "properties-panel"
      assert Scenes.get_connection(scene.id, connection.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Task 6: Layer Visibility on Canvas
  # ---------------------------------------------------------------------------

  describe "layer bar" do
    setup :register_and_log_in_user

    test "layer popover props expose the scene layers", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      layer_props = get_layer_list_props(view)
      # Default layer is auto-created with the scene
      assert layer_props["layers"] != []
    end

    test "renders correct number of layers", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      Scenes.create_layer(scene.id, %{name: "Second Layer"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      layer_props = get_layer_list_props(view)
      assert Enum.any?(layer_props["layers"], &(&1["name"] == "Second Layer"))
    end

    test "add layer button creates new layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "create_layer", %{})

      layer_props = get_layer_list_props(view)
      assert Enum.any?(layer_props["layers"], &(&1["name"] == "New Layer"))
      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 2
    end
  end

  describe "set_active_layer event" do
    setup :register_and_log_in_user

    test "updates active layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, new_layer} = Scenes.create_layer(scene.id, %{name: "Layer 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_active_layer", %{"id" => to_string(new_layer.id)})

      layer_props = get_layer_list_props(view)
      assert layer_props["active-layer-id"] == new_layer.id
    end

    test "new pin gets active layer_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, new_layer} = Scenes.create_layer(scene.id, %{name: "Layer 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Set active layer
      render_click(view, "set_active_layer", %{"id" => to_string(new_layer.id)})

      # Create pin
      render_hook(view, "create_pin", %{"position_x" => 50.0, "position_y" => 50.0})

      pins = Scenes.list_pins(scene.id)
      assert length(pins) == 1
      [pin] = pins
      assert pin.layer_id == new_layer.id
    end

    test "new zone gets active layer_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, new_layer} = Scenes.create_layer(scene.id, %{name: "Layer 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Set active layer
      render_click(view, "set_active_layer", %{"id" => to_string(new_layer.id)})

      # Create zone
      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"name" => "Layered Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert zone.layer_id == new_layer.id
    end
  end

  # ---------------------------------------------------------------------------
  # Task 7: Zone Vertex Editing + Interaction Polish
  # ---------------------------------------------------------------------------

  describe "update_zone_vertices event" do
    setup :register_and_log_in_user

    test "updates zone vertices with valid data", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Editable Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 80.0, "y" => 20.0},
        %{"x" => 80.0, "y" => 80.0},
        %{"x" => 20.0, "y" => 80.0}
      ]

      render_hook(view, "update_zone_vertices", %{
        "id" => zone.id,
        "vertices" => new_vertices
      })

      updated = Scenes.get_zone!(zone.id)
      assert length(updated.vertices) == 4
    end

    test "rejects vertices with fewer than 3 points", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      bad_vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 50.0}
      ]

      html =
        render_hook(view, "update_zone_vertices", %{
          "id" => zone.id,
          "vertices" => bad_vertices
        })

      assert html =~ "Invalid zone"

      # Original vertices should be unchanged
      unchanged = Scenes.get_zone!(zone.id)
      assert length(unchanged.vertices) == 3
    end

    test "accepts vertex updates with out-of-canvas coordinates", %{conn: conn, user: user} do
      # V2 removed the 0-100 clamp: elements may live outside the canvas.
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      new_vertices = [
        %{"x" => -5.0, "y" => 10.0},
        %{"x" => 110.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 50.0}
      ]

      render_hook(view, "update_zone_vertices", %{
        "id" => zone.id,
        "vertices" => new_vertices
      })

      updated = Scenes.get_zone!(zone.id)
      assert length(updated.vertices) == 3
      xs = Enum.map(updated.vertices, & &1["x"])
      assert -5.0 in xs
      assert 110.0 in xs
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 80.0, "y" => 20.0},
        %{"x" => 50.0, "y" => 80.0}
      ]

      render_hook(view, "update_zone_vertices", %{
        "id" => zone.id,
        "vertices" => new_vertices
      })

      # Original vertices should be unchanged (3 original default vertices)
      unchanged = Scenes.get_zone!(zone.id)
      assert length(unchanged.vertices) == 3
    end

    test "accepts shifted vertices simulating zone drag", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      # Create zone with known vertices
      zone =
        zone_fixture(scene, %{
          "name" => "Drag Me",
          "vertices" => [
            %{"x" => 20.0, "y" => 20.0},
            %{"x" => 40.0, "y" => 20.0},
            %{"x" => 40.0, "y" => 40.0},
            %{"x" => 20.0, "y" => 40.0}
          ]
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Shift all vertices by +30 (simulating drag)
      shifted_vertices = [
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 70.0, "y" => 50.0},
        %{"x" => 70.0, "y" => 70.0},
        %{"x" => 50.0, "y" => 70.0}
      ]

      render_hook(view, "update_zone_vertices", %{
        "id" => zone.id,
        "vertices" => shifted_vertices
      })

      updated = Scenes.get_zone!(zone.id)
      assert length(updated.vertices) == 4

      # Verify all vertices are within bounds
      Enum.each(updated.vertices, fn v ->
        assert v["x"] >= 0 and v["x"] <= 100
        assert v["y"] >= 0 and v["y"] <= 100
      end)

      # Verify the shift happened
      [first | _] = updated.vertices
      assert_in_delta first["x"], 50.0, 0.01
      assert_in_delta first["y"], 50.0, 0.01
    end
  end

  describe "tooltip data in serialization" do
    setup :register_and_log_in_user

    test "pin tooltip included in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle", "tooltip" => "A grand castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [pin_data] = scene_data["pins"]
      assert pin_data["tooltip"] == "A grand castle"
    end

    test "zone tooltip included in data-scene JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone = zone_fixture(scene, %{"name" => "Forest", "tooltip" => "A dark forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [zone_data] = scene_data["zones"]
      assert zone_data["tooltip"] == "A dark forest"
    end
  end

  describe "toggle_layer_visibility event" do
    setup :register_and_log_in_user

    test "toggles layer visibility", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Toggle off
      render_click(view, "toggle_layer_visibility", %{"id" => to_string(layer.id)})

      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.visible == false

      # Toggle back on
      render_click(view, "toggle_layer_visibility", %{"id" => to_string(layer.id)})

      updated2 = Scenes.get_layer!(scene.id, layer.id)
      assert updated2.visible == true
    end

    test "hidden layer is reflected in tree panel layers prop", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "toggle_layer_visibility", %{"id" => to_string(layer.id)})

      layer_props = get_layer_list_props(view)
      hidden = Enum.find(layer_props["layers"], &(&1["id"] == layer.id))
      assert hidden["visible"] == false
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 3 Fixes — Task 8: Missing Tests
  # ---------------------------------------------------------------------------

  describe "delete_layer event" do
    setup :register_and_log_in_user

    test "deletes layer when more than one exists", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, extra_layer} = Scenes.create_layer(scene.id, %{name: "Extra Layer"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "delete_layer", %{"id" => to_string(extra_layer.id)})

      assert html =~ "Layer deleted"
      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 1
    end

    test "deleting the default layer refreshes layer props and active layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [default_layer] = Scenes.list_layers(scene.id)
      {:ok, extra_layer} = Scenes.create_layer(scene.id, %{name: "Extra Layer"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "delete_layer", %{"id" => to_string(default_layer.id)})

      assert html =~ "Layer deleted"

      layer_props = get_layer_list_props(view)
      refute Enum.any?(layer_props["layers"], &(&1["id"] == default_layer.id))
      assert Enum.any?(layer_props["layers"], &(&1["id"] == extra_layer.id))
      assert layer_props["active-layer-id"] == extra_layer.id
    end

    test "cannot delete the last layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [only_layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "delete_layer", %{"id" => to_string(only_layer.id)})

      assert html =~ "Cannot delete the last layer"
      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 1
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      {:ok, _extra} = Scenes.create_layer(scene.id, %{name: "Extra"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      [_, extra | _] = Scenes.list_layers(scene.id)
      render_click(view, "delete_layer", %{"id" => to_string(extra.id)})

      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 2
    end
  end

  describe "move_pin viewer rejection" do
    setup :register_and_log_in_user

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"position_x" => 10.0, "position_y" => 20.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      unchanged = Scenes.get_pin!(pin.id)
      assert_in_delta unchanged.position_x, 10.0, 0.01
      assert_in_delta unchanged.position_y, 20.0, 0.01
    end
  end

  describe "update_connection viewer rejection" do
    setup :register_and_log_in_user

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_connection", %{
        "id" => to_string(connection.id),
        "field" => "label",
        "value" => "Hacked"
      })

      unchanged = Scenes.get_connection!(scene.id, connection.id)
      assert unchanged.label != "Hacked"
    end
  end

  describe "select_element with invalid ID" do
    setup :register_and_log_in_user

    test "handles non-existent pin gracefully", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "select_element", %{"type" => "pin", "id" => 999_999})

      # Should not crash; no properties panel shown
      refute html =~ "properties-panel"
    end

    test "handles non-existent zone gracefully", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "select_element", %{"type" => "zone", "id" => 999_999})

      refute html =~ "properties-panel"
    end

    test "handles non-existent connection gracefully", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "select_element", %{"type" => "connection", "id" => 999_999})

      refute html =~ "properties-panel"
    end
  end

  describe "IDOR prevention — scoped element queries" do
    setup :register_and_log_in_user

    test "update_pin with pin from another scene is silently ignored (IDOR blocked)", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Scene A"})
      other_scene = scene_fixture(project, %{name: "Scene B"})
      other_pin = pin_fixture(other_scene, %{"label" => "Other"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # The scoped get_pin/2 returns nil, so the handler is a no-op
      render_hook(view, "update_pin", %{
        "id" => to_string(other_pin.id),
        "field" => "label",
        "value" => "Hacked"
      })

      # Pin should be unchanged
      unchanged = Scenes.get_pin!(other_pin.id)
      assert unchanged.label == "Other"
    end

    test "select_element with element from another scene returns nothing", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Scene A"})
      other_scene = scene_fixture(project, %{name: "Scene B"})
      other_pin = pin_fixture(other_scene, %{"label" => "Other"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # select_element uses non-bang query, so it returns nil — no panel shown
      html = render_hook(view, "select_element", %{"type" => "pin", "id" => other_pin.id})
      refute html =~ "properties-panel"
    end
  end

  describe "navigate_to_target event" do
    setup :register_and_log_in_user

    test "navigates to another scene", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Source Scene"})
      target_scene = scene_fixture(project, %{name: "Target Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => target_scene.id})

      assert_patch(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{target_scene.id}"
      )
    end

    test "ignores unsupported target types", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Should not crash
      html = render_hook(view, "navigate_to_target", %{"type" => "sheet", "id" => 1})
      assert html =~ "scene-canvas"
    end
  end

  describe "background upload handlers" do
    setup :register_and_log_in_user

    test "remove_background clears background_asset_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/bg.png"})
      scene = scene_fixture(project)
      {:ok, scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "remove_background", %{})

      updated = Scenes.get_scene(project.id, scene.id)
      assert is_nil(updated.background_asset_id)
    end

    test "attach_background_asset sets background_asset_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/bg.png"})
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "attach_background_asset", %{"asset_id" => asset.id})

      updated = Scenes.get_scene(project.id, scene.id)
      assert updated.background_asset_id == asset.id
    end

    test "remove_background rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      asset = image_asset_fixture(project, owner, %{url: "https://example.com/bg.png"})
      scene = scene_fixture(project)
      {:ok, scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "remove_background", %{})

      unchanged = Scenes.get_scene(project.id, scene.id)
      assert unchanged.background_asset_id == asset.id
    end

    test "attach_background_asset rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      asset = image_asset_fixture(project, owner, %{url: "https://example.com/bg.png"})
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "attach_background_asset", %{"asset_id" => asset.id})

      unchanged = Scenes.get_scene(project.id, scene.id)
      assert is_nil(unchanged.background_asset_id)
    end
  end

  describe "duplicate_zone event" do
    setup :register_and_log_in_user

    test "creates new zone with shifted vertices and copy suffix", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      zone =
        zone_fixture(scene, %{
          "name" => "Forest",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 30.0}
          ],
          "fill_color" => "#00ff00",
          "opacity" => 0.6
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "duplicate_zone", %{"id" => to_string(zone.id)})

      assert html =~ "Zone duplicated"

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 2

      copy = Enum.find(zones, fn z -> z.id != zone.id end)
      assert copy.name == "Forest (copy)"
      assert copy.fill_color == "#00ff00"
      assert_in_delta copy.opacity, 0.6, 0.01
      assert length(copy.vertices) == 3

      # Vertices should be shifted by +5
      [v1 | _] = copy.vertices
      assert_in_delta v1["x"], 15.0, 0.01
      assert_in_delta v1["y"], 15.0, 0.01
    end

    test "original zone unchanged after duplication", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      zone =
        zone_fixture(scene, %{
          "name" => "Castle",
          "vertices" => [
            %{"x" => 20.0, "y" => 20.0},
            %{"x" => 40.0, "y" => 20.0},
            %{"x" => 40.0, "y" => 40.0}
          ]
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "duplicate_zone", %{"id" => to_string(zone.id)})

      original = Scenes.get_zone!(zone.id)
      assert original.name == "Castle"
      [v1 | _] = original.vertices
      assert_in_delta v1["x"], 20.0, 0.01
      assert_in_delta v1["y"], 20.0, 0.01
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Protected"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "duplicate_zone", %{"id" => to_string(zone.id)})

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
    end
  end

  describe "scene_data serialization — new fields" do
    setup :register_and_log_in_user

    test "SceneCanvas exposes can-edit true for editor", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      canvas = get_scene_canvas_vue(view)
      assert canvas.props["can-edit"] == true
    end

    test "SceneCanvas exposes can-edit false for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      canvas = get_scene_canvas_vue(view)
      assert canvas.props["can-edit"] == false
    end

    test "pin serialization includes flow_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      flow = flow_fixture(project)

      pin = pin_fixture(scene, %{"label" => "Linked Pin"})

      {:ok, _} = Scenes.update_pin(pin, %{"flow_id" => flow.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [pin_data] = scene_data["pins"]
      assert pin_data["flow_id"] == flow.id
    end

    test "zone serialization includes target_type and target_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      target_scene = scene_fixture(project, %{name: "Target"})

      zone = zone_fixture(scene, %{"name" => "Linked Zone"})

      {:ok, _} =
        Scenes.update_zone(zone, %{"target_type" => "scene", "target_id" => target_scene.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [zone_data] = scene_data["zones"]
      assert zone_data["target_type"] == "scene"
      assert zone_data["target_id"] == target_scene.id
    end
  end

  describe "create_pin_from_sheet event" do
    setup :register_and_log_in_user

    test "creates pin linked to sheet", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      sheet = sheet_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select a sheet first, then place pin
      render_click(view, "start_pin_from_sheet", %{"sheet-id" => to_string(sheet.id)})
      render_hook(view, "create_pin_from_sheet", %{"position_x" => 40.0, "position_y" => 60.0})

      pins = Scenes.list_pins(scene.id)
      assert length(pins) == 1
      [pin] = pins
      assert pin.sheet_id == sheet.id
      assert pin.label == sheet.name
      assert pin.pin_type == "character"
    end

    test "pin serialization includes avatar_url when sheet has avatar", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      avatar = image_asset_fixture(project, user, %{url: "https://example.com/avatar.png"})
      sheet = sheet_fixture(project)
      {:ok, _} = Storyarn.Sheets.add_avatar(sheet, avatar.id, %{is_default: true})
      scene = scene_fixture(project)

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "sheet_id" => sheet.id
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [pin_data] = scene_data["pins"]
      assert pin_data["sheet_id"] == sheet.id
      assert pin_data["sheet_avatar_url"] == "https://example.com/avatar.png"
    end

    test "pin serialization handles sheet without avatar", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)
      scene = scene_fixture(project)

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "sheet_id" => sheet.id
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [pin_data] = scene_data["pins"]
      assert pin_data["sheet_id"] == sheet.id
      assert is_nil(pin_data["sheet_avatar_url"])
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_pin_from_sheet", %{"position_x" => 50.0, "position_y" => 50.0})

      pins = Scenes.list_pins(scene.id)
      assert pins == []
    end
  end

  describe "create_annotation event" do
    setup :register_and_log_in_user

    test "creates annotation with valid coordinates", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_annotation", %{"position_x" => 40.0, "position_y" => 60.0})

      annotations = Scenes.list_annotations(scene.id)
      assert length(annotations) == 1
      [annotation] = annotations
      assert_in_delta annotation.position_x, 40.0, 0.01
      assert_in_delta annotation.position_y, 60.0, 0.01
      assert annotation.text == "Note"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "create_annotation", %{"position_x" => 50.0, "position_y" => 50.0})

      assert Scenes.list_annotations(scene.id) == []
    end
  end

  describe "update_annotation event" do
    setup :register_and_log_in_user

    test "updates annotation text", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene, %{"text" => "Original"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_annotation", %{
        "id" => to_string(annotation.id),
        "field" => "text",
        "value" => "Updated text"
      })

      updated = Scenes.get_annotation!(scene.id, annotation.id)
      assert updated.text == "Updated text"
    end
  end

  describe "delete_annotation event" do
    setup :register_and_log_in_user

    test "removes annotation", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "delete_annotation", %{"id" => to_string(annotation.id)})

      assert Scenes.get_annotation(scene.id, annotation.id) == nil
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "delete_annotation", %{"id" => to_string(annotation.id)})

      assert Scenes.get_annotation(scene.id, annotation.id)
    end
  end

  describe "annotation serialization" do
    setup :register_and_log_in_user

    test "annotation serialized in scene_data JSON", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      _annotation =
        annotation_fixture(scene, %{
          "text" => "My note",
          "position_x" => 25.0,
          "position_y" => 75.0,
          "font_size" => "lg",
          "color" => "#ff0000"
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      assert length(scene_data["annotations"]) == 1
      [ann_data] = scene_data["annotations"]
      assert ann_data["text"] == "My note"
      assert ann_data["position_x"] == 25.0
      assert ann_data["position_y"] == 75.0
      assert ann_data["font_size"] == "lg"
      assert ann_data["color"] == "#ff0000"
    end
  end

  describe "update_connection_waypoints event" do
    setup :register_and_log_in_user

    test "updates waypoints", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      waypoints = [%{"x" => 30.0, "y" => 40.0}, %{"x" => 60.0, "y" => 20.0}]

      render_hook(view, "update_connection_waypoints", %{
        "id" => to_string(connection.id),
        "waypoints" => waypoints
      })

      updated = Scenes.get_connection!(scene.id, connection.id)
      assert length(updated.waypoints) == 2
    end

    test "clear_connection_waypoints resets to empty", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, _} =
        Scenes.update_connection_waypoints(connection, %{
          "waypoints" => [%{"x" => 50.0, "y" => 50.0}]
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "clear_connection_waypoints", %{"id" => to_string(connection.id)})

      updated = Scenes.get_connection!(scene.id, connection.id)
      assert updated.waypoints == []
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_connection_waypoints", %{
        "id" => to_string(connection.id),
        "waypoints" => [%{"x" => 50.0, "y" => 50.0}]
      })

      unchanged = Scenes.get_connection!(scene.id, connection.id)
      assert unchanged.waypoints == []
    end
  end

  describe "connection serialization — waypoints" do
    setup :register_and_log_in_user

    test "connection serialization includes waypoints", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, _} =
        Scenes.update_connection_waypoints(connection, %{
          "waypoints" => [%{"x" => 25.0, "y" => 75.0}]
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [conn_data] = scene_data["connections"]
      assert length(conn_data["waypoints"]) == 1
      assert hd(conn_data["waypoints"])["x"] == 25.0
    end

    test "connection serialization defaults to empty waypoints", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      _connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [conn_data] = scene_data["connections"]
      assert conn_data["waypoints"] == []
    end
  end

  # ---------------------------------------------------------------------------
  # Phase B Task 3: Search & Filter
  # ---------------------------------------------------------------------------

  describe "search_elements event" do
    setup :register_and_log_in_user

    test "returns matching pins by label", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Castle Gate"})
      pin2 = pin_fixture(scene, %{"label" => "Forest Camp"})
      pin3 = pin_fixture(scene, %{"label" => "Castle Tower"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "search_elements", %{"query" => "castle"})

      pin_ids = search_result_ids(view, "pin")
      assert pin1.id in pin_ids
      assert pin3.id in pin_ids
      refute pin2.id in pin_ids
    end

    test "returns matching zones by name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Dark Forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "search_elements", %{"query" => "forest"})

      assert zone.id in search_result_ids(view, "zone")
    end

    test "returns matching annotations by text", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      ann = annotation_fixture(scene, %{"text" => "Important meeting point"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "search_elements", %{"query" => "meeting"})

      assert ann.id in search_result_ids(view, "annotation")
    end

    test "returns matching connections by label", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      conn_record = connection_fixture(scene, pin1, pin2, %{"label" => "Trade Route"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "search_elements", %{"query" => "trade"})

      assert conn_record.id in search_result_ids(view, "connection")
    end

    test "empty query clears results", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # First search
      render_hook(view, "search_elements", %{"query" => "castle"})
      assert pin.id in search_result_ids(view, "pin")

      # Then clear
      render_hook(view, "search_elements", %{"query" => ""})
      assert get_search_panel_vue(view).props["search-results"] == []
    end

    test "shows no results when nothing matches", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "search_elements", %{"query" => "nonexistent"})

      panel = get_search_panel_vue(view)
      assert panel.props["search-query"] == "nonexistent"
      assert panel.props["search-results"] == []
    end
  end

  describe "set_search_filter event" do
    setup :register_and_log_in_user

    test "filters results by type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Forest Pin"})
      zone = zone_fixture(scene, %{"name" => "Forest Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Search for "forest" — should find both
      render_hook(view, "search_elements", %{"query" => "forest"})
      assert pin.id in search_result_ids(view, "pin")
      assert zone.id in search_result_ids(view, "zone")

      # Filter to pins only
      render_click(view, "set_search_filter", %{"filter" => "pin"})
      assert pin.id in search_result_ids(view, "pin")
      assert search_result_ids(view, "zone") == []
    end
  end

  describe "clear_search event" do
    setup :register_and_log_in_user

    test "resets search state", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Search first
      render_hook(view, "search_elements", %{"query" => "castle"})
      assert pin.id in search_result_ids(view, "pin")

      # Clear
      render_click(view, "clear_search", %{})

      panel = get_search_panel_vue(view)
      assert panel.props["search-query"] == ""
      assert panel.props["search-results"] == []
    end
  end

  describe "focus_search_result event" do
    setup :register_and_log_in_user

    test "selects the element", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Target Pin"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "focus_search_result", %{
        "type" => "pin",
        "id" => to_string(pin.id)
      })

      panel = get_element_panel_vue(view)
      assert panel.props["selected-type"] == "pin"
      assert panel.props["selected-element"]["label"] == "Target Pin"
    end

    test "handles non-existent element gracefully", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "focus_search_result", %{
          "type" => "pin",
          "id" => "999999"
        })

      refute html =~ "properties-panel"
    end
  end

  # ---------------------------------------------------------------------------
  # Phase B Task 4: Auto-Generated Legend
  # ---------------------------------------------------------------------------

  describe "legend" do
    setup :register_and_log_in_user

    test "renders legend button when scene has elements", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      legend = get_legend_vue(view)
      assert legend.props["legend-data"]["hasEntries"] == true
    end

    test "legend data is empty when scene has no elements", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      legend = get_legend_vue(view)
      assert legend.props["legend-data"]["hasEntries"] == false
      assert legend.props["legend-data"]["pinGroups"] == []
      assert legend.props["legend-data"]["zoneGroups"] == []
      assert legend.props["legend-data"]["connectionGroups"] == []
    end

    test "toggle_legend flips the legend-open prop", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle", "pin_type" => "location"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Initially closed
      assert get_legend_vue(view).props["legend-open"] == false

      # Expand
      render_click(view, "toggle_legend", %{})
      legend = get_legend_vue(view)
      assert legend.props["legend-open"] == true
      assert [%{"label" => "Location"} | _] = legend.props["legend-data"]["pinGroups"]

      # Collapse again
      render_click(view, "toggle_legend", %{})
      assert get_legend_vue(view).props["legend-open"] == false
    end

    test "shows pin type groupings", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin1 = pin_fixture(scene, %{"label" => "Castle", "pin_type" => "location"})
      _pin2 = pin_fixture(scene, %{"label" => "Hero", "pin_type" => "character"})
      _pin3 = pin_fixture(scene, %{"label" => "Town", "pin_type" => "location"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Expand legend
      html = render_click(view, "toggle_legend", %{})

      # Should show Location (count 2) and Character (count 1)
      assert html =~ "Location"
      assert html =~ "Character"
      assert html =~ "2"
      assert html =~ "1"
    end

    test "shows zone color groupings", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone1 = zone_fixture(scene, %{"name" => "Forest", "fill_color" => "#00ff00"})
      _zone2 = zone_fixture(scene, %{"name" => "Lake", "fill_color" => "#0000ff"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      legend = get_legend_vue(view)
      colors = Enum.map(legend.props["legend-data"]["zoneGroups"], & &1["color"])
      assert "#00ff00" in colors
      assert "#0000ff" in colors
    end

    test "shows connection style groupings", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      pin3 = pin_fixture(scene, %{"label" => "C"})
      _conn1 = connection_fixture(scene, pin1, pin2, %{"line_style" => "solid"})
      _conn2 = connection_fixture(scene, pin2, pin3, %{"line_style" => "dashed"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      legend = get_legend_vue(view)
      styles = Enum.map(legend.props["legend-data"]["connectionGroups"], & &1["lineStyle"])
      assert "solid" in styles
      assert "dashed" in styles
    end
  end

  describe "image pins (icon_asset)" do
    setup :register_and_log_in_user

    test "pin serialization includes icon_asset_url when set", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      asset = asset_fixture(project, user, %{url: "/uploads/castle-icon.png"})
      _pin = pin_fixture(scene, %{"label" => "Castle", "icon_asset_id" => asset.id})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "castle-icon.png"
    end

    test "pin serialization handles nil icon_asset_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Plain Pin"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [pin_data] = scene_data["pins"]
      assert Map.has_key?(pin_data, "icon_asset_url")
      assert is_nil(pin_data["icon_asset_url"])
    end

    test "remove_pin_icon clears the icon_asset_id", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      asset = asset_fixture(project, user, %{url: "/uploads/castle-icon.png"})
      pin = pin_fixture(scene, %{"label" => "Castle", "icon_asset_id" => asset.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select the pin
      render_click(view, "select_element", %{"type" => "pin", "id" => "#{pin.id}"})

      # Remove the icon
      render_click(view, "remove_pin_icon", %{})

      # Verify icon was removed
      updated = Scenes.get_pin!(scene.id, pin.id)
      assert is_nil(updated.icon_asset_id)
    end

    test "toggle_pin_icon_upload does not crash", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select the pin
      render_click(view, "select_element", %{"type" => "pin", "id" => "#{pin.id}"})

      # Toggle on/off — the upload panel state is internal to the Vue
      # ElementPropertiesPanel, so we just verify the handler exists and
      # doesn't crash the LiveView.
      render_click(view, "toggle_pin_icon_upload", %{})
      render_click(view, "toggle_pin_icon_upload", %{})

      assert get_scene_canvas_vue(view).component == "modules/scenes/editor/components/canvas/SceneCanvas"
    end
  end

  describe "fog of war" do
    setup :register_and_log_in_user

    test "update_layer_fog enables fog on a layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "update_layer_fog", %{
        "id" => "#{layer.id}",
        "field" => "fog_enabled",
        "value" => "true"
      })

      # Verify persisted
      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.fog_enabled == true

      # And reflected in the tree panel layers prop
      layer_props = get_layer_list_props(view)
      updated_layer = Enum.find(layer_props["layers"], &(&1["id"] == layer.id))
      assert updated_layer["fogEnabled"] == true
    end

    test "update_layer_fog updates fog color and opacity", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "update_layer_fog", %{
        "id" => "#{layer.id}",
        "field" => "fog_color",
        "value" => "#ff0000"
      })

      render_click(view, "update_layer_fog", %{
        "id" => "#{layer.id}",
        "field" => "fog_opacity",
        "value" => "0.5"
      })

      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.fog_color == "#ff0000"
      assert updated.fog_opacity == 0.5
    end

    test "update_layer_fog rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "update_layer_fog", %{
          "id" => "#{layer.id}",
          "field" => "fog_enabled",
          "value" => "true"
        })

      assert html =~ "permission"

      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.fog_enabled == false
    end

    test "layer serialization includes fog fields", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)
      [layer_data | _] = scene_data["layers"]
      assert Map.has_key?(layer_data, "fog_enabled")
      assert Map.has_key?(layer_data, "fog_color")
      assert Map.has_key?(layer_data, "fog_opacity")
    end
  end

  describe "rename_layer event" do
    setup :register_and_log_in_user

    test "renames layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "rename_layer", %{
          "id" => to_string(layer.id),
          "value" => "Renamed Layer"
        })

      assert html =~ "Layer renamed"
      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.name == "Renamed Layer"
    end

    test "renames layer from Vue payload", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_hook(view, "rename_layer", %{
          "id" => layer.id,
          "name" => "Walking areas"
        })

      assert html =~ "Layer renamed"
      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.name == "Walking areas"
    end

    test "ignores empty name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)
      original_name = layer.name

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "rename_layer", %{
        "id" => to_string(layer.id),
        "value" => "   "
      })

      unchanged = Scenes.get_layer!(scene.id, layer.id)
      assert unchanged.name == original_name
    end

    test "ignores same name", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "rename_layer", %{
          "id" => to_string(layer.id),
          "value" => layer.name
        })

      # No flash when name unchanged
      refute html =~ "Layer renamed"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)
      original_name = layer.name

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "rename_layer", %{
        "id" => to_string(layer.id),
        "value" => "Hacked Name"
      })

      unchanged = Scenes.get_layer!(scene.id, layer.id)
      assert unchanged.name == original_name
    end
  end

  describe "confirm_delete_layer event" do
    setup :register_and_log_in_user

    test "deletes layer via confirm flow", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, extra_layer} = Scenes.create_layer(scene.id, %{name: "Extra Layer"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Set pending then confirm
      render_click(view, "set_pending_delete_layer", %{"id" => to_string(extra_layer.id)})
      html = render_click(view, "confirm_delete_layer", %{})

      assert html =~ "Layer deleted"
      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 1
    end

    test "does nothing without pending layer", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Confirm without setting pending — should be a no-op
      html = render_click(view, "confirm_delete_layer", %{})
      refute html =~ "Layer deleted"
    end
  end

  # ---------------------------------------------------------------------------
  # Ruler / Distance Measurement
  # ---------------------------------------------------------------------------

  describe "ruler / scene scale" do
    setup :register_and_log_in_user

    test "update_scene_scale persists scale settings", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "update_scene_scale", %{
        "field" => "scale_value",
        "value" => "500"
      })

      render_click(view, "update_scene_scale", %{
        "field" => "scale_unit",
        "value" => "km"
      })

      updated = Scenes.get_scene!(project.id, scene.id)
      assert updated.scale_value == 500.0
      assert updated.scale_unit == "km"
    end

    test "update_scene_scale rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      membership_fixture(project, user, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "update_scene_scale", %{
          "field" => "scale_value",
          "value" => "500"
        })

      assert html =~ "permission"
    end

    test "scene data serialization includes scale fields", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{scale_unit: "leagues", scale_value: 100.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(view)

      assert scene_data["scale_unit"] == "leagues"
      assert scene_data["scale_value"] == 100.0
    end

    test "ruler tool can be activated via set_tool", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "set_tool", %{"type" => "ruler"})

      canvas = get_scene_canvas_vue(view)
      assert canvas.props["active-tool"] == "ruler"
    end

    test "set_tool accepts ruler", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Should not crash
      render_click(view, "set_tool", %{"type" => "ruler"})
    end
  end

  describe "scene export" do
    setup :register_and_log_in_user

    test "export_scene event works for editor", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # The export buttons live in the SceneHeaderActions Vue component (client-side).
      # Verify both: the SceneHeaderActions component is mounted, and the server
      # handler accepts the export_scene event without crashing.
      actions = LiveVue.Test.get_vue(view, name: "live/scene/show/SceneHeaderActions")
      assert actions.component == "live/scene/show/SceneHeaderActions"

      render_click(view, "export_scene", %{"format" => "png"})
      render_click(view, "export_scene", %{"format" => "svg"})
    end

    test "export_scene event works for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Export is available to viewers (read-only export path).
      actions = LiveVue.Test.get_vue(view, name: "live/scene/show/SceneHeaderActions")
      assert actions.props["can-edit"] == false

      render_click(view, "export_scene", %{"format" => "png"})
    end

    test "export_scene event pushes export to client", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Should not crash — the push_event goes to JS
      render_click(view, "export_scene", %{"format" => "png"})
      render_click(view, "export_scene", %{"format" => "svg"})
    end
  end

  # ---------------------------------------------------------------------------
  # Lock guards
  # ---------------------------------------------------------------------------

  describe "locked element guards" do
    setup :register_and_log_in_user

    test "move_pin on locked pin is a no-op", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"position_x" => 10.0, "position_y" => 20.0})
      {:ok, pin} = Scenes.update_pin(pin, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      unchanged = Scenes.get_pin!(pin.id)
      assert_in_delta unchanged.position_x, 10.0, 0.01
      assert_in_delta unchanged.position_y, 20.0, 0.01
    end

    test "delete_pin on locked pin returns error flash", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)
      {:ok, _pin} = Scenes.update_pin(pin, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "delete_pin", %{"id" => to_string(pin.id)})

      assert html =~ "Cannot delete a locked element"
      assert Scenes.get_pin(pin.id)
    end

    test "update_pin with field locked toggles the lock", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "locked",
        "toggle" => "true"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.locked == true
    end

    test "delete_zone on locked zone returns error flash", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)
      {:ok, _zone} = Scenes.update_zone(zone, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "delete_zone", %{"id" => to_string(zone.id)})

      assert html =~ "Cannot delete a locked element"
      assert Scenes.get_zone(zone.id)
    end

    test "update_zone_vertices on locked zone is a no-op", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)
      original_vertices = zone.vertices
      {:ok, _zone} = Scenes.update_zone(zone, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "update_zone_vertices", %{
        "id" => to_string(zone.id),
        "vertices" => [
          %{"x" => 0.0, "y" => 0.0},
          %{"x" => 100.0, "y" => 0.0},
          %{"x" => 50.0, "y" => 100.0}
        ]
      })

      unchanged = Scenes.get_zone!(zone.id)
      assert unchanged.vertices == original_vertices
    end

    test "move_annotation on locked annotation is a no-op", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene, %{"position_x" => 10.0, "position_y" => 20.0})
      {:ok, _annotation} = Scenes.update_annotation(annotation, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "move_annotation", %{
        "id" => to_string(annotation.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      unchanged = Scenes.get_annotation!(scene.id, annotation.id)
      assert_in_delta unchanged.position_x, 10.0, 0.01
      assert_in_delta unchanged.position_y, 20.0, 0.01
    end

    test "delete_annotation on locked annotation returns error flash", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)
      {:ok, _annotation} = Scenes.update_annotation(annotation, %{"locked" => true})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "delete_annotation", %{"id" => to_string(annotation.id)})

      assert html =~ "Cannot delete a locked element"
      assert Scenes.get_annotation(scene.id, annotation.id)
    end
  end

  describe "version history events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "History Scene"})
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"

      %{project: project, scene: scene, url: url}
    end

    test "creates a named version", %{conn: conn, url: url, scene: scene} do
      view = mount_scene(conn, url)

      render_click(view, "create_version", %{
        "title" => "First milestone",
        "description" => "Initial playable scene"
      })

      version = Versioning.get_version("scene", scene.id, 1)
      assert version.title == "First milestone"
      assert version.description == "Initial playable scene"
      refute version.is_auto
    end

    test "restores the scene from the selected version", %{
      conn: conn,
      user: user,
      project: project,
      url: url,
      scene: scene
    } do
      {:ok, version} =
        Versioning.create_version("scene", scene, project.id, user.id, title: "Before rename")

      {:ok, _changed_scene} = Scenes.update_scene(scene, %{"name" => "Changed Scene"})
      view = mount_scene(conn, url)

      render_click(view, "confirm_restore", %{
        "version_number" => to_string(version.version_number),
        "skip_pre_snapshot" => true
      })

      restored = Scenes.get_scene(project.id, scene.id)
      assert restored.name == "History Scene"
    end
  end

  defp mount_scene(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end
end
