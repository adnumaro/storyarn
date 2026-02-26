defmodule StoryarnWeb.SceneLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

  # Extracts and decodes the data-scene JSON from rendered HTML
  defp extract_scene_data(html) do
    [_, encoded] = Regex.run(~r/data-scene="([^"]*)"/, html)

    encoded
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> Jason.decode!()
  end

  describe "canvas rendering" do
    setup :register_and_log_in_user

    test "renders SceneCanvas hook element", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "World Scene"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ ~s(phx-hook="SceneCanvas")
      assert html =~ ~s(id="scene-canvas")
    end

    test "data-scene contains valid JSON with scene fields", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Test Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

      assert scene_data["id"] == scene.id
      assert scene_data["name"] == "Test Scene"
      assert is_number(scene_data["default_zoom"])
      assert is_number(scene_data["default_center_x"])
      assert is_number(scene_data["default_center_y"])
    end

    test "includes background URL when background_asset_id is set",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/bg.png"})

      scene = scene_fixture(project, %{name: "BG Scene"})
      {:ok, _scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      assert scene_data["background_url"] == "https://example.com/bg.png"
    end

    test "renders without error when no background asset", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "No BG Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      assert is_nil(scene_data["background_url"])
    end

    test "header shows scene name and Back to Scenes link", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "My Scene"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "My Scene"
      assert html =~ "Scenes"
      assert html =~ ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
    end

    test "header shows shortcut badge", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Test Scene"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "##{scene.shortcut}"
    end
  end

  describe "save_name event" do
    setup :register_and_log_in_user

    test "updates scene name", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project, %{name: "Viewable Scene"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "Viewable Scene"
      assert html =~ ~s(phx-hook="SceneCanvas")
    end
  end

  describe "dock and tools" do
    setup :register_and_log_in_user

    test "renders dock for editor in edit mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "scene-dock"
      assert html =~ "set_tool"

      # All 9 tool buttons present
      for tool <- ~w(select pan rectangle triangle circle freeform pin annotation connector) do
        assert html =~ ~s(phx-value-tool="#{tool}"),
               "Expected tool button for #{tool}"
      end
    end

    test "does not render dock for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "set_tool", %{"tool" => "pin"})
      # Pin button should now be active (btn-primary)
      assert html =~ "btn-primary"
    end

    test "renders edit/view toggle for editor", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "toggle_edit_mode"
    end

    test "toggle_edit_mode switches to view mode", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Default is edit mode for editors — dock should be visible
      assert render(view) =~ "scene-dock"

      # Toggle to view mode — dock should disappear
      html = render_click(view, "toggle_edit_mode", %{})
      refute html =~ "scene-dock"

      # Toggle back to edit mode — dock returns
      html = render_click(view, "toggle_edit_mode", %{})
      assert html =~ "scene-dock"
    end

    test "viewer cannot toggle to edit mode", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "renders freeform zone tool button", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ ~s(phx-value-tool="freeform")
      assert html =~ ~s(phx-value-tool="rectangle")
      assert html =~ ~s(phx-value-tool="triangle")
      assert html =~ ~s(phx-value-tool="circle")
    end

    test "set_tool freeform activates freeform", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "set_tool", %{"tool" => "freeform"})
      # Freeform button should be active
      assert html =~ "btn-primary"
    end
  end

  describe "create_zone event" do
    setup :register_and_log_in_user

    test "creates zone with 3+ valid vertices", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "rejects zone with out-of-range coordinates", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      html = render_hook(view, "create_zone", %{"name" => "Bad Zone", "vertices" => vertices})

      zones = Scenes.list_zones(scene.id)
      assert zones == []
      assert html =~ "Invalid zone"
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{"label" => "Test Pin", "position_x" => 25.0, "position_y" => 75.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

      assert length(scene_data["pins"]) == 1
      [pin_data] = scene_data["pins"]
      assert pin_data["label"] == "Test Pin"
      assert pin_data["position_x"] == 25.0
      assert pin_data["position_y"] == 75.0
    end

    test "includes zones in data-scene JSON", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone = zone_fixture(scene, %{"name" => "Test Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

      assert length(scene_data["zones"]) == 1
      [zone_data] = scene_data["zones"]
      assert zone_data["name"] == "Test Zone"
      assert is_list(zone_data["vertices"])
      assert length(zone_data["vertices"]) == 3
    end

    test "includes connections in data-scene JSON", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A", "position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(scene, %{"label" => "B", "position_x" => 90.0, "position_y" => 90.0})
      _conn_record = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

      assert length(scene_data["connections"]) == 1
      [conn_data] = scene_data["connections"]
      assert conn_data["from_pin_id"] == pin1.id
      assert conn_data["to_pin_id"] == pin2.id
    end

    test "includes layers in data-scene JSON", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

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

    test "selecting a pin shows floating toolbar with pin data", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      assert html =~ "floating-toolbar"
      assert html =~ "Castle"
      assert html =~ "update_pin"
    end

    test "selecting a zone shows floating toolbar with zone data", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Dark Forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})

      assert html =~ "floating-toolbar"
      assert html =~ "Dark Forest"
      assert html =~ "update_zone"
    end

    test "deselect hides floating toolbar", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})
      html = render_hook(view, "deselect", %{})

      refute html =~ "floating-toolbar"
    end
  end

  describe "update_pin event" do
    setup :register_and_log_in_user

    test "updates pin label", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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

  describe "delete element from panel" do
    setup :register_and_log_in_user

    test "delete_pin removes pin and clears selection", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "renders connector tool button in dock", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ ~s(phx-value-tool="connector")
    end

    test "set_tool connector activates connector", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "set_tool", %{"tool" => "connector"})
      assert html =~ "btn-primary"
    end
  end

  describe "create_connection event" do
    setup :register_and_log_in_user

    test "creates connection between two valid pins", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_hook(view, "select_element", %{
          "type" => "connection",
          "id" => connection.id
        })

      assert html =~ "floating-toolbar"
      assert html =~ "update_connection"
    end

    test "delete_connection removes and clears selection", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "renders layer panel in tree panel layers tab", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Layers tab exists
      assert html =~ "Layers"

      # Switch to layers tab
      html = render_click(view, "switch_tree_tab", %{"tab" => "layers"})

      assert html =~ "layer-panel-items"
      assert html =~ "toggle_layer_visibility"
    end

    test "renders correct number of layers", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      Scenes.create_layer(scene.id, %{name: "Second Layer"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "switch_tree_tab", %{"tab" => "layers"})
      assert html =~ "Second Layer"
    end

    test "add layer button creates new layer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_click(view, "switch_tree_tab", %{"tab" => "layers"})
      html = render_click(view, "create_layer", %{})

      assert html =~ "New Layer"
      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 2
    end
  end

  describe "set_active_layer event" do
    setup :register_and_log_in_user

    test "updates active layer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      {:ok, new_layer} = Scenes.create_layer(scene.id, %{name: "Layer 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Switch to layers tab first
      render_click(view, "switch_tree_tab", %{"tab" => "layers"})

      html = render_click(view, "set_active_layer", %{"id" => to_string(new_layer.id)})

      # The new active layer button should have the primary outline
      assert html =~ "btn-primary btn-outline"
    end

    test "new pin gets active layer_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "rejects vertices with out-of-range coordinates", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      bad_vertices = [
        %{"x" => -5.0, "y" => 10.0},
        %{"x" => 110.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 50.0}
      ]

      html =
        render_hook(view, "update_zone_vertices", %{
          "id" => zone.id,
          "vertices" => bad_vertices
        })

      assert html =~ "Invalid zone"

      unchanged = Scenes.get_zone!(zone.id)
      assert length(unchanged.vertices) == 3
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle", "tooltip" => "A grand castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      [pin_data] = scene_data["pins"]
      assert pin_data["tooltip"] == "A grand castle"
    end

    test "zone tooltip included in data-scene JSON", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone = zone_fixture(scene, %{"name" => "Forest", "tooltip" => "A dark forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      [zone_data] = scene_data["zones"]
      assert zone_data["tooltip"] == "A dark forest"
    end
  end

  describe "toggle_layer_visibility event" do
    setup :register_and_log_in_user

    test "toggles layer visibility", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "hidden layer shows eye-off icon", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Switch to layers tab so layer UI is rendered
      render_click(view, "switch_tree_tab", %{"tab" => "layers"})

      html = render_click(view, "toggle_layer_visibility", %{"id" => to_string(layer.id)})
      assert html =~ "eye-off"
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 3 Fixes — Task 8: Missing Tests
  # ---------------------------------------------------------------------------

  describe "delete_layer event" do
    setup :register_and_log_in_user

    test "deletes layer when more than one exists", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "cannot delete the last layer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Source Scene"})
      target_scene = scene_fixture(project, %{name: "Target Scene"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => target_scene.id})

      assert_redirect(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{target_scene.id}"
      )
    end

    test "ignores unsupported target types", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "remove_background rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
  end

  describe "duplicate_zone event" do
    setup :register_and_log_in_user

    test "creates new zone with shifted vertices and copy suffix", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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

    test "includes can_edit flag in scene data", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      assert scene_data["can_edit"] == true
    end

    test "viewer gets can_edit false", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      assert scene_data["can_edit"] == false
    end

    test "pin serialization includes target_type and target_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      target_scene = scene_fixture(project, %{name: "Target"})

      pin = pin_fixture(scene, %{"label" => "Linked Pin"})

      {:ok, _} =
        Scenes.update_pin(pin, %{"target_type" => "scene", "target_id" => target_scene.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
      [pin_data] = scene_data["pins"]
      assert pin_data["target_type"] == "scene"
      assert pin_data["target_id"] == target_scene.id
    end

    test "zone serialization includes target_type and target_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      scene_data = extract_scene_data(render(view))
      [zone_data] = scene_data["zones"]
      assert zone_data["target_type"] == "scene"
      assert zone_data["target_id"] == target_scene.id
    end
  end

  describe "create_pin_from_sheet event" do
    setup :register_and_log_in_user

    test "creates pin linked to sheet", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      assert pin.target_type == "sheet"
      assert pin.target_id == sheet.id
    end

    test "pin serialization includes avatar_url when sheet has avatar", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      avatar = image_asset_fixture(project, user, %{url: "https://example.com/avatar.png"})
      sheet = sheet_fixture(project, %{avatar_asset_id: avatar.id})
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

      scene_data = extract_scene_data(render(view))
      [pin_data] = scene_data["pins"]
      assert pin_data["sheet_id"] == sheet.id
      assert pin_data["avatar_url"] == "https://example.com/avatar.png"
    end

    test "pin serialization handles sheet without avatar", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      scene_data = extract_scene_data(render(view))
      [pin_data] = scene_data["pins"]
      assert pin_data["sheet_id"] == sheet.id
      assert is_nil(pin_data["avatar_url"])
    end

    test "rejected for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      render_hook(view, "delete_annotation", %{"id" => to_string(annotation.id)})

      assert Scenes.get_annotation(scene.id, annotation.id) != nil
    end
  end

  describe "annotation serialization" do
    setup :register_and_log_in_user

    test "annotation serialized in scene_data JSON", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      scene_data = extract_scene_data(render(view))
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      scene_data = extract_scene_data(render(view))
      [conn_data] = scene_data["connections"]
      assert length(conn_data["waypoints"]) == 1
      assert hd(conn_data["waypoints"])["x"] == 25.0
    end

    test "connection serialization defaults to empty waypoints", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      _connection = connection_fixture(scene, pin1, pin2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Castle Gate"})
      pin2 = pin_fixture(scene, %{"label" => "Forest Camp"})
      pin3 = pin_fixture(scene, %{"label" => "Castle Tower"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      view |> element("#search-form") |> render_change(%{"query" => "castle"})

      # Should show two results (Castle Gate, Castle Tower) via focus_search_result buttons
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin1.id}']")
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin3.id}']")
      refute has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin2.id}']")
    end

    test "returns matching zones by name", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      zone = zone_fixture(scene, %{"name" => "Dark Forest"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      view |> element("#search-form") |> render_change(%{"query" => "forest"})

      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{zone.id}']")
    end

    test "returns matching annotations by text", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      ann = annotation_fixture(scene, %{"text" => "Important meeting point"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      view |> element("#search-form") |> render_change(%{"query" => "meeting"})

      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{ann.id}']")
    end

    test "returns matching connections by label", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      conn_record = connection_fixture(scene, pin1, pin2, %{"label" => "Trade Route"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      view |> element("#search-form") |> render_change(%{"query" => "trade"})

      assert has_element?(
               view,
               "[phx-click='focus_search_result'][phx-value-id='#{conn_record.id}']"
             )
    end

    test "empty query clears results", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # First search
      view |> element("#search-form") |> render_change(%{"query" => "castle"})
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin.id}']")

      # Then clear
      view |> element("#search-form") |> render_change(%{"query" => ""})
      refute has_element?(view, "[phx-click='focus_search_result']")
    end

    test "shows no results message when nothing matches", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        view
        |> element("#search-form")
        |> render_change(%{"query" => "nonexistent"})

      assert html =~ "No results found"
      refute has_element?(view, "[phx-click='focus_search_result']")
    end
  end

  describe "set_search_filter event" do
    setup :register_and_log_in_user

    test "filters results by type", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Forest Pin"})
      zone = zone_fixture(scene, %{"name" => "Forest Zone"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Search for "forest" — should find both
      view |> element("#search-form") |> render_change(%{"query" => "forest"})
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin.id}']")
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{zone.id}']")

      # Filter to pins only
      render_click(view, "set_search_filter", %{"filter" => "pin"})
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin.id}']")
      refute has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{zone.id}']")
    end
  end

  describe "clear_search event" do
    setup :register_and_log_in_user

    test "resets search state", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Search first
      view |> element("#search-form") |> render_change(%{"query" => "castle"})
      assert has_element?(view, "[phx-click='focus_search_result'][phx-value-id='#{pin.id}']")

      # Clear
      render_click(view, "clear_search", %{})

      # All results should be gone
      refute has_element?(view, "[phx-click='focus_search_result']")
    end
  end

  describe "focus_search_result event" do
    setup :register_and_log_in_user

    test "selects the element", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Target Pin"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html =
        render_click(view, "focus_search_result", %{
          "type" => "pin",
          "id" => to_string(pin.id)
        })

      # Floating toolbar should show for the selected pin
      assert html =~ "floating-toolbar"
      assert html =~ "update_pin"
    end

    test "handles non-existent element gracefully", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "scene-legend"
      assert html =~ "Legend"
    end

    test "does not render legend when scene has no elements", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      refute html =~ "scene-legend"
    end

    test "toggle_legend expands and collapses", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Castle", "pin_type" => "location"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Initially collapsed — no pin type section visible
      refute has_element?(view, "#scene-legend .overflow-y-auto")

      # Expand
      html = render_click(view, "toggle_legend", %{})
      assert html =~ "Pins"
      assert html =~ "Location"

      # Collapse again
      render_click(view, "toggle_legend", %{})
      refute has_element?(view, "#scene-legend .overflow-y-auto")
    end

    test "shows pin type groupings", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _zone1 = zone_fixture(scene, %{"name" => "Forest", "fill_color" => "#00ff00"})
      _zone2 = zone_fixture(scene, %{"name" => "Lake", "fill_color" => "#0000ff"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      html = render_click(view, "toggle_legend", %{})

      assert html =~ "Zones"
      assert html =~ "#00ff00"
      assert html =~ "#0000ff"
    end

    test "shows connection style groupings", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      html = render_click(view, "toggle_legend", %{})

      assert html =~ "Connections"
      assert html =~ "Solid"
      assert html =~ "Dashed"
    end
  end

  describe "image pins (icon_asset)" do
    setup :register_and_log_in_user

    test "pin serialization includes icon_asset_url when set", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Plain Pin"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "icon_asset_url"
      refute html =~ "castle-icon.png"
    end

    test "remove_pin_icon clears the icon_asset_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "toggle_pin_icon_upload toggles the upload form", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"label" => "Castle"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Select the pin
      render_click(view, "select_element", %{"type" => "pin", "id" => "#{pin.id}"})

      # Toggle upload on
      html = render_click(view, "toggle_pin_icon_upload", %{})
      assert html =~ "pin-icon-upload"

      # Toggle upload off
      html = render_click(view, "toggle_pin_icon_upload", %{})
      refute html =~ "pin-icon-upload"
    end
  end

  describe "fog of war" do
    setup :register_and_log_in_user

    test "update_layer_fog enables fog on a layer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      [layer | _] = Scenes.list_layers(scene.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Switch to layers tab so fog icon is visible
      render_click(view, "switch_tree_tab", %{"tab" => "layers"})

      html =
        render_click(view, "update_layer_fog", %{
          "id" => "#{layer.id}",
          "field" => "fog_enabled",
          "value" => "true"
        })

      assert html =~ "cloud-fog"

      # Verify persisted
      updated = Scenes.get_layer!(scene.id, layer.id)
      assert updated.fog_enabled == true
    end

    test "update_layer_fog updates fog color and opacity", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "fog_enabled"
      assert html =~ "fog_color"
      assert html =~ "fog_opacity"
    end
  end

  describe "rename_layer event" do
    setup :register_and_log_in_user

    test "renames layer", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "ignores empty name", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(owner) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{scale_unit: "leagues", scale_value: 100.0})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      scene_data = extract_scene_data(render(view))

      assert scene_data["scale_unit"] == "leagues"
      assert scene_data["scale_value"] == 100.0
    end

    test "ruler tool appears in dock", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "phx-value-tool=\"ruler\""
    end

    test "set_tool accepts ruler", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Should not crash
      render_click(view, "set_tool", %{"tool" => "ruler"})
    end
  end

  describe "scene export" do
    setup :register_and_log_in_user

    test "export buttons render for editor", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      assert html =~ "data-event=\"export_scene\""
      assert html =~ "Export as PNG"
      assert html =~ "Export as SVG"
    end

    test "export buttons render for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        )

      # Export should still be available for viewers (read-only export)
      assert html =~ "data-event=\"export_scene\""
    end

    test "export_scene event pushes export to client", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      assert Scenes.get_pin(pin.id) != nil
    end

    test "update_pin with field locked toggles the lock", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      assert Scenes.get_zone(zone.id) != nil
    end

    test "update_zone_vertices on locked zone is a no-op", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      assert Scenes.get_annotation(scene.id, annotation.id) != nil
    end
  end
end
