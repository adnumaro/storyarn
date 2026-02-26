defmodule StoryarnWeb.SceneLive.Handlers.UndoRedoHandlersTest do
  @moduledoc """
  Tests for UndoRedoHandlers — covers undo/redo of pin, zone, connection,
  annotation, and layer operations through the scene LiveView, plus unit
  tests for push_undo, push_undo_coalesced, and stack management.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers

  # -------------------------------------------------------------------
  # Shared setup helpers
  # -------------------------------------------------------------------

  defp scene_url(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp setup_scene(%{conn: conn, user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    scene = scene_fixture(project)
    {:ok, project: project, scene: scene, conn: conn, user: user}
  end

  defp mock_socket(extra_assigns \\ %{}) do
    base = %{
      __changed__: %{},
      undo_stack: [],
      redo_stack: []
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, extra_assigns)}
  end

  # =====================================================================
  # UNIT TESTS: push_undo / push_undo_coalesced / stack helpers
  # =====================================================================

  describe "push_undo/2 (unit)" do
    test "pushes an action onto the undo stack and clears redo" do
      socket = mock_socket(%{redo_stack: [{:delete_pin, :fake}]})
      result = UndoRedoHandlers.push_undo(socket, {:delete_zone, :some_zone})

      assert [{:delete_zone, :some_zone}] = result.assigns.undo_stack
      assert [] = result.assigns.redo_stack
    end

    test "stacks multiple undo actions in LIFO order" do
      socket =
        mock_socket()
        |> UndoRedoHandlers.push_undo({:delete_pin, :pin_a})
        |> UndoRedoHandlers.push_undo({:delete_pin, :pin_b})

      assert [{:delete_pin, :pin_b}, {:delete_pin, :pin_a}] = socket.assigns.undo_stack
    end
  end

  describe "push_undo_no_clear/2 (unit)" do
    test "pushes onto undo stack without clearing redo" do
      socket = mock_socket(%{redo_stack: [{:delete_zone, :z}]})
      result = UndoRedoHandlers.push_undo_no_clear(socket, {:delete_pin, :p})

      assert [{:delete_pin, :p}] = result.assigns.undo_stack
      assert [{:delete_zone, :z}] = result.assigns.redo_stack
    end
  end

  describe "push_redo/2 (unit)" do
    test "pushes onto redo stack" do
      socket = mock_socket()
      result = UndoRedoHandlers.push_redo(socket, {:delete_pin, :pin_a})

      assert [{:delete_pin, :pin_a}] = result.assigns.redo_stack
    end
  end

  describe "push_undo_coalesced/2 — move_pin (unit)" do
    test "first push creates a normal undo entry" do
      socket = mock_socket()
      prev = %{x: 10.0, y: 20.0}
      new = %{x: 30.0, y: 40.0}

      result = UndoRedoHandlers.push_undo_coalesced(socket, {:move_pin, "pin1", prev, new})

      assert [{:move_pin, "pin1", ^prev, ^new}] = result.assigns.undo_stack
    end

    test "consecutive moves for the same pin coalesce — preserving original prev" do
      prev1 = %{x: 10.0, y: 20.0}
      mid = %{x: 30.0, y: 40.0}
      final = %{x: 50.0, y: 60.0}

      socket =
        mock_socket()
        |> UndoRedoHandlers.push_undo_coalesced({:move_pin, "pin1", prev1, mid})
        |> UndoRedoHandlers.push_undo_coalesced({:move_pin, "pin1", mid, final})

      # Should coalesce: original prev1 + final new
      assert [{:move_pin, "pin1", ^prev1, ^final}] = socket.assigns.undo_stack
    end

    test "moves for different pins do not coalesce" do
      socket =
        mock_socket()
        |> UndoRedoHandlers.push_undo_coalesced({:move_pin, "pin1", %{x: 0, y: 0}, %{x: 1, y: 1}})
        |> UndoRedoHandlers.push_undo_coalesced({:move_pin, "pin2", %{x: 5, y: 5}, %{x: 6, y: 6}})

      assert length(socket.assigns.undo_stack) == 2
    end
  end

  describe "push_undo_coalesced/2 — move_annotation (unit)" do
    test "consecutive moves for the same annotation coalesce" do
      prev1 = %{x: 10.0, y: 20.0}
      mid = %{x: 30.0, y: 40.0}
      final = %{x: 50.0, y: 60.0}

      socket =
        mock_socket()
        |> UndoRedoHandlers.push_undo_coalesced({:move_annotation, "ann1", prev1, mid})
        |> UndoRedoHandlers.push_undo_coalesced({:move_annotation, "ann1", mid, final})

      assert [{:move_annotation, "ann1", ^prev1, ^final}] = socket.assigns.undo_stack
    end

    test "moves for different annotations do not coalesce" do
      socket =
        mock_socket()
        |> UndoRedoHandlers.push_undo_coalesced(
          {:move_annotation, "a1", %{x: 0, y: 0}, %{x: 1, y: 1}}
        )
        |> UndoRedoHandlers.push_undo_coalesced(
          {:move_annotation, "a2", %{x: 5, y: 5}, %{x: 6, y: 6}}
        )

      assert length(socket.assigns.undo_stack) == 2
    end
  end

  describe "UndoRedoStack.init/1 (unit)" do
    test "initializes empty stacks on socket" do
      socket = UndoRedoStack.init(mock_socket(%{undo_stack: [:junk], redo_stack: [:junk]}))

      assert socket.assigns.undo_stack == []
      assert socket.assigns.redo_stack == []
    end
  end

  describe "UndoRedoStack.can_undo?/1 and can_redo?/1 (unit)" do
    test "returns false for empty stacks" do
      socket = mock_socket()
      refute UndoRedoStack.can_undo?(socket)
      refute UndoRedoStack.can_redo?(socket)
    end

    test "returns true for non-empty stacks" do
      socket = mock_socket(%{undo_stack: [:something], redo_stack: [:something]})
      assert UndoRedoStack.can_undo?(socket)
      assert UndoRedoStack.can_redo?(socket)
    end
  end

  describe "UndoRedoStack.clear/1 (unit)" do
    test "clears both stacks" do
      socket = UndoRedoStack.clear(mock_socket(%{undo_stack: [:a], redo_stack: [:b]}))

      assert socket.assigns.undo_stack == []
      assert socket.assigns.redo_stack == []
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo pin deletion
  # =====================================================================

  describe "undo/redo pin deletion" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores a deleted pin, redo re-deletes it", ctx do
      pin =
        pin_fixture(ctx.scene, %{
          "label" => "Undoable Pin",
          "position_x" => 25.0,
          "position_y" => 35.0
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Delete the pin
      render_hook(view, "delete_pin", %{"id" => to_string(pin.id)})
      assert Scenes.list_pins(ctx.scene.id) == []

      # Undo — pin should be restored
      render_hook(view, "undo", %{})
      pins = Scenes.list_pins(ctx.scene.id)
      assert length(pins) == 1

      restored = hd(pins)
      assert restored.label == "Undoable Pin"
      assert restored.position_x == 25.0
      assert restored.position_y == 35.0

      # Redo — pin should be deleted again
      render_hook(view, "redo", %{})
      assert Scenes.list_pins(ctx.scene.id) == []
    end

    test "undo on empty stack is a no-op", ctx do
      _pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Undo with nothing to undo
      render_hook(view, "undo", %{})

      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end

    test "redo on empty stack is a no-op", ctx do
      _pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Redo with nothing to redo
      render_hook(view, "redo", %{})

      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo zone deletion
  # =====================================================================

  describe "undo/redo zone deletion" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores a deleted zone, redo re-deletes it", ctx do
      zone = zone_fixture(ctx.scene, %{"name" => "Forest"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_zone", %{"id" => to_string(zone.id)})
      assert Scenes.list_zones(ctx.scene.id) == []

      # Undo — zone restored
      render_hook(view, "undo", %{})
      zones = Scenes.list_zones(ctx.scene.id)
      assert length(zones) == 1
      assert hd(zones).name == "Forest"

      # Redo — zone deleted again
      render_hook(view, "redo", %{})
      assert Scenes.list_zones(ctx.scene.id) == []
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo connection deletion
  # =====================================================================

  describe "undo/redo connection deletion" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores a deleted connection, redo re-deletes it", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_connection", %{"id" => to_string(conn_rec.id)})
      assert Scenes.list_connections(ctx.scene.id) == []

      # Undo — connection restored
      render_hook(view, "undo", %{})
      conns = Scenes.list_connections(ctx.scene.id)
      assert length(conns) == 1

      restored = hd(conns)
      assert restored.from_pin_id == pin1.id
      assert restored.to_pin_id == pin2.id

      # Redo — connection deleted again
      render_hook(view, "redo", %{})
      assert Scenes.list_connections(ctx.scene.id) == []
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo annotation deletion
  # =====================================================================

  describe "undo/redo annotation deletion" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores a deleted annotation, redo re-deletes it", ctx do
      ann =
        annotation_fixture(ctx.scene, %{
          "text" => "Important Note",
          "position_x" => 42.0,
          "position_y" => 58.0
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_annotation", %{"id" => to_string(ann.id)})
      assert Scenes.list_annotations(ctx.scene.id) == []

      # Undo — annotation restored
      render_hook(view, "undo", %{})
      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 1
      assert hd(annotations).text == "Important Note"

      # Redo — annotation deleted again
      render_hook(view, "redo", %{})
      assert Scenes.list_annotations(ctx.scene.id) == []
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo pin creation (reverts create by deleting)
  # =====================================================================

  describe "undo/redo pin creation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo of create_pin removes the pin, redo re-creates it", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Create a pin via the LiveView event
      render_hook(view, "create_pin", %{"position_x" => 40.0, "position_y" => 60.0})
      pins = Scenes.list_pins(ctx.scene.id)
      assert length(pins) == 1

      # Undo — pin creation reverted
      render_hook(view, "undo", %{})
      assert Scenes.list_pins(ctx.scene.id) == []

      # Redo — pin re-created
      render_hook(view, "redo", %{})
      pins = Scenes.list_pins(ctx.scene.id)
      assert length(pins) == 1
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo zone creation
  # =====================================================================

  describe "undo/redo zone creation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo of create_zone removes the zone, redo re-creates it", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "create_zone", %{"vertices" => vertices, "name" => "Meadow"})
      assert length(Scenes.list_zones(ctx.scene.id)) == 1

      # Undo — zone removed
      render_hook(view, "undo", %{})
      assert Scenes.list_zones(ctx.scene.id) == []

      # Redo — zone re-created
      render_hook(view, "redo", %{})
      zones = Scenes.list_zones(ctx.scene.id)
      assert length(zones) == 1
      assert hd(zones).name == "Meadow"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo pin update (field change)
  # =====================================================================

  describe "undo/redo pin update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous pin label, redo re-applies new label", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Original"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Update label
      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "label",
        "value" => "Renamed"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.label == "Renamed"

      # Undo — label reverted
      render_hook(view, "undo", %{})
      reverted = Scenes.get_pin!(ctx.scene.id, pin.id)
      assert reverted.label == "Original"

      # Redo — label changed again
      render_hook(view, "redo", %{})
      re_applied = Scenes.get_pin!(ctx.scene.id, pin.id)
      assert re_applied.label == "Renamed"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo zone update (field change)
  # =====================================================================

  describe "undo/redo zone update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous zone name, redo re-applies it", ctx do
      zone = zone_fixture(ctx.scene, %{"name" => "Swamp"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "name",
        "value" => "Desert"
      })

      assert Scenes.get_zone!(zone.id).name == "Desert"

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.get_zone!(ctx.scene.id, zone.id).name == "Swamp"

      # Redo
      render_hook(view, "redo", %{})
      assert Scenes.get_zone!(ctx.scene.id, zone.id).name == "Desert"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo zone vertices update
  # =====================================================================

  describe "undo/redo zone vertices update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous vertices, redo re-applies new ones", ctx do
      original_vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      zone = zone_fixture(ctx.scene, %{"name" => "Polygon", "vertices" => original_vertices})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 60.0, "y" => 20.0},
        %{"x" => 40.0, "y" => 60.0}
      ]

      render_hook(view, "update_zone_vertices", %{
        "id" => to_string(zone.id),
        "vertices" => new_vertices
      })

      updated = Scenes.get_zone!(zone.id)
      assert length(updated.vertices) == 3
      assert hd(updated.vertices)["x"] == 20.0

      # Undo
      render_hook(view, "undo", %{})
      reverted = Scenes.get_zone!(ctx.scene.id, zone.id)
      assert hd(reverted.vertices)["x"] == 10.0

      # Redo
      render_hook(view, "redo", %{})
      re_applied = Scenes.get_zone!(ctx.scene.id, zone.id)
      assert hd(re_applied.vertices)["x"] == 20.0
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo connection update (field change)
  # =====================================================================

  describe "undo/redo connection update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous connection label, redo re-applies it", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2, %{"label" => "Path A"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection", %{
        "id" => to_string(conn_rec.id),
        "field" => "label",
        "value" => "Path B"
      })

      assert Scenes.get_connection!(conn_rec.id).label == "Path B"

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.get_connection!(ctx.scene.id, conn_rec.id).label == "Path A"

      # Redo
      render_hook(view, "redo", %{})
      assert Scenes.get_connection!(ctx.scene.id, conn_rec.id).label == "Path B"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo annotation update
  # =====================================================================

  describe "undo/redo annotation update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous annotation text, redo re-applies it", ctx do
      ann = annotation_fixture(ctx.scene, %{"text" => "Draft"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_annotation", %{
        "id" => to_string(ann.id),
        "field" => "text",
        "value" => "Final"
      })

      assert Scenes.get_annotation!(ann.id).text == "Final"

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.get_annotation!(ctx.scene.id, ann.id).text == "Draft"

      # Redo
      render_hook(view, "redo", %{})
      assert Scenes.get_annotation!(ctx.scene.id, ann.id).text == "Final"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo pin move
  # =====================================================================

  describe "undo/redo pin move" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous pin position, redo re-applies move", ctx do
      pin = pin_fixture(ctx.scene, %{"position_x" => 20.0, "position_y" => 30.0})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 70.0,
        "position_y" => 80.0
      })

      moved = Scenes.get_pin!(pin.id)
      assert moved.position_x == 70.0
      assert moved.position_y == 80.0

      # Undo — position reverted
      render_hook(view, "undo", %{})
      reverted = Scenes.get_pin!(ctx.scene.id, pin.id)
      assert reverted.position_x == 20.0
      assert reverted.position_y == 30.0

      # Redo — move re-applied
      render_hook(view, "redo", %{})
      re_moved = Scenes.get_pin!(ctx.scene.id, pin.id)
      assert re_moved.position_x == 70.0
      assert re_moved.position_y == 80.0
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo annotation move
  # =====================================================================

  describe "undo/redo annotation move" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous annotation position, redo re-applies move", ctx do
      ann = annotation_fixture(ctx.scene, %{"position_x" => 15.0, "position_y" => 25.0})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "move_annotation", %{
        "id" => to_string(ann.id),
        "position_x" => 65.0,
        "position_y" => 75.0
      })

      moved = Scenes.get_annotation!(ann.id)
      assert moved.position_x == 65.0
      assert moved.position_y == 75.0

      # Undo
      render_hook(view, "undo", %{})
      reverted = Scenes.get_annotation!(ctx.scene.id, ann.id)
      assert reverted.position_x == 15.0
      assert reverted.position_y == 25.0

      # Redo
      render_hook(view, "redo", %{})
      re_moved = Scenes.get_annotation!(ctx.scene.id, ann.id)
      assert re_moved.position_x == 65.0
      assert re_moved.position_y == 75.0
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo layer creation
  # =====================================================================

  describe "undo/redo layer creation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo of create_layer removes the layer, redo re-creates it", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      initial_count = length(Scenes.list_layers(ctx.scene.id))

      render_hook(view, "create_layer", %{})
      assert length(Scenes.list_layers(ctx.scene.id)) == initial_count + 1

      # Undo — layer removed
      render_hook(view, "undo", %{})
      assert length(Scenes.list_layers(ctx.scene.id)) == initial_count

      # Redo — layer re-created
      render_hook(view, "redo", %{})
      assert length(Scenes.list_layers(ctx.scene.id)) == initial_count + 1
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo layer deletion
  # =====================================================================

  describe "undo/redo layer deletion" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores a deleted layer, redo re-deletes it", ctx do
      # Create a second layer so we can delete it (cannot delete the last layer)
      extra_layer = layer_fixture(ctx.scene, %{"name" => "Removable Layer"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      initial_count = length(Scenes.list_layers(ctx.scene.id))

      render_hook(view, "delete_layer", %{"id" => to_string(extra_layer.id)})
      assert length(Scenes.list_layers(ctx.scene.id)) == initial_count - 1

      # Undo — layer restored
      render_hook(view, "undo", %{})
      layers = Scenes.list_layers(ctx.scene.id)
      assert length(layers) == initial_count
      assert Enum.any?(layers, &(&1.name == "Removable Layer"))

      # Redo — layer deleted again
      render_hook(view, "redo", %{})
      assert length(Scenes.list_layers(ctx.scene.id)) == initial_count - 1
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo layer rename
  # =====================================================================

  describe "undo/redo layer rename" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous layer name, redo re-applies it", ctx do
      layer = layer_fixture(ctx.scene, %{"name" => "Ground"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "rename_layer", %{
        "id" => to_string(layer.id),
        "value" => "Sky"
      })

      assert Scenes.get_layer!(ctx.scene.id, layer.id).name == "Sky"

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.get_layer!(ctx.scene.id, layer.id).name == "Ground"

      # Redo
      render_hook(view, "redo", %{})
      assert Scenes.get_layer!(ctx.scene.id, layer.id).name == "Sky"
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo layer fog update
  # =====================================================================

  describe "undo/redo layer fog update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous fog_enabled, redo re-applies it", ctx do
      layer = layer_fixture(ctx.scene, %{"name" => "Fog Layer"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_layer_fog", %{
        "id" => to_string(layer.id),
        "field" => "fog_enabled",
        "value" => "true"
      })

      assert Scenes.get_layer!(ctx.scene.id, layer.id).fog_enabled == true

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.get_layer!(ctx.scene.id, layer.id).fog_enabled == false

      # Redo
      render_hook(view, "redo", %{})
      assert Scenes.get_layer!(ctx.scene.id, layer.id).fog_enabled == true
    end
  end

  # =====================================================================
  # INTEGRATION: Compound undo (pin deletion with associated connections)
  # =====================================================================

  describe "compound undo — pin deletion cascades connections" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores pin and its connections, redo re-deletes all", ctx do
      pin1 =
        pin_fixture(ctx.scene, %{"label" => "Hub", "position_x" => 50.0, "position_y" => 50.0})

      pin2 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      _conn1 = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Delete pin1 — its connections should also be deleted
      render_hook(view, "delete_pin", %{"id" => to_string(pin1.id)})
      assert Scenes.list_pins(ctx.scene.id) |> length() == 1
      assert Scenes.list_connections(ctx.scene.id) == []

      # Undo — pin and connection restored (compound)
      render_hook(view, "undo", %{})
      assert Scenes.list_pins(ctx.scene.id) |> length() == 2
      assert Scenes.list_connections(ctx.scene.id) |> length() == 1

      # Redo — all deleted again
      render_hook(view, "redo", %{})
      assert Scenes.list_pins(ctx.scene.id) |> length() == 1
      assert Scenes.list_connections(ctx.scene.id) == []
    end
  end

  # =====================================================================
  # INTEGRATION: Multiple undo/redo operations
  # =====================================================================

  describe "multiple sequential undos and redos" do
    setup [:register_and_log_in_user, :setup_scene]

    test "can undo and redo multiple operations in sequence", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Create pin 1
      render_hook(view, "create_pin", %{"position_x" => 10.0, "position_y" => 10.0})
      assert length(Scenes.list_pins(ctx.scene.id)) == 1

      # Create pin 2
      render_hook(view, "create_pin", %{"position_x" => 20.0, "position_y" => 20.0})
      assert length(Scenes.list_pins(ctx.scene.id)) == 2

      # Undo pin 2 creation
      render_hook(view, "undo", %{})
      assert length(Scenes.list_pins(ctx.scene.id)) == 1

      # Undo pin 1 creation
      render_hook(view, "undo", %{})
      assert Scenes.list_pins(ctx.scene.id) == []

      # Redo pin 1 creation
      render_hook(view, "redo", %{})
      assert length(Scenes.list_pins(ctx.scene.id)) == 1

      # Redo pin 2 creation
      render_hook(view, "redo", %{})
      assert length(Scenes.list_pins(ctx.scene.id)) == 2
    end

    test "new action after undo clears redo stack", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Create and then undo
      render_hook(view, "create_pin", %{"position_x" => 10.0, "position_y" => 10.0})
      render_hook(view, "undo", %{})
      assert Scenes.list_pins(ctx.scene.id) == []

      # Perform a new action — this should clear the redo stack
      render_hook(view, "create_pin", %{"position_x" => 50.0, "position_y" => 50.0})
      assert length(Scenes.list_pins(ctx.scene.id)) == 1

      # Redo should be a no-op (redo stack was cleared by the new create)
      render_hook(view, "redo", %{})
      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end
  end

  # =====================================================================
  # INTEGRATION: Connection waypoints undo/redo
  # =====================================================================

  describe "undo/redo connection waypoints" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo restores previous waypoints, redo re-applies new ones", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      new_waypoints = [%{"x" => 50.0, "y" => 30.0}, %{"x" => 50.0, "y" => 70.0}]

      render_hook(view, "update_connection_waypoints", %{
        "id" => to_string(conn_rec.id),
        "waypoints" => new_waypoints
      })

      updated = Scenes.get_connection!(conn_rec.id)
      assert length(updated.waypoints) == 2

      # Undo
      render_hook(view, "undo", %{})
      reverted = Scenes.get_connection!(ctx.scene.id, conn_rec.id)
      assert reverted.waypoints == [] || reverted.waypoints == nil

      # Redo
      render_hook(view, "redo", %{})
      re_applied = Scenes.get_connection!(ctx.scene.id, conn_rec.id)
      assert length(re_applied.waypoints) == 2
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo connection creation
  # =====================================================================

  describe "undo/redo connection creation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo of create_connection removes it, redo re-creates it", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "create_connection", %{
        "from_pin_id" => to_string(pin1.id),
        "to_pin_id" => to_string(pin2.id)
      })

      assert length(Scenes.list_connections(ctx.scene.id)) == 1

      # Undo — connection removed
      render_hook(view, "undo", %{})
      assert Scenes.list_connections(ctx.scene.id) == []

      # Redo — connection re-created
      render_hook(view, "redo", %{})
      assert length(Scenes.list_connections(ctx.scene.id)) == 1
    end
  end

  # =====================================================================
  # INTEGRATION: Undo/redo annotation creation
  # =====================================================================

  describe "undo/redo annotation creation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "undo of create_annotation removes it, redo re-creates it", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "create_annotation", %{
        "text" => "My Note",
        "position_x" => 33.0,
        "position_y" => 44.0
      })

      assert length(Scenes.list_annotations(ctx.scene.id)) == 1

      # Undo
      render_hook(view, "undo", %{})
      assert Scenes.list_annotations(ctx.scene.id) == []

      # Redo
      render_hook(view, "redo", %{})
      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 1
      assert hd(annotations).text == "My Note"
    end
  end
end
