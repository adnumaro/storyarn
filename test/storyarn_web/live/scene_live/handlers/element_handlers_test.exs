defmodule StoryarnWeb.SceneLive.Handlers.ElementHandlersTest do
  @moduledoc """
  Tests for ElementHandlers — focuses on handler functions not already
  covered by show_test.exs: pending-delete confirmation flow,
  zone/pin action & condition handlers, keyboard shortcuts
  (delete/duplicate/copy/paste), sheet picker, and edge cases.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

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

  # -------------------------------------------------------------------
  # Pending-delete confirmation flow
  # -------------------------------------------------------------------

  describe "pending delete + confirm_delete_element (pin)" do
    setup [:register_and_log_in_user, :setup_scene]

    test "set_pending_delete_pin + confirm_delete_element deletes the pin", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Doomed Pin"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Mark for deletion
      render_hook(view, "set_pending_delete_pin", %{"id" => to_string(pin.id)})

      # Confirm
      render_hook(view, "confirm_delete_element", %{})

      assert Scenes.list_pins(ctx.scene.id) == []
    end

    test "confirm_delete_element with no pending element is a no-op", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Without setting pending, confirm does nothing
      render_hook(view, "confirm_delete_element", %{})

      assert length(Scenes.list_pins(ctx.scene.id)) == 1
      assert Scenes.get_pin!(pin.id)
    end
  end

  describe "pending delete + confirm_delete_element (zone)" do
    setup [:register_and_log_in_user, :setup_scene]

    test "set_pending_delete_zone + confirm deletes the zone", ctx do
      zone = zone_fixture(ctx.scene, %{"name" => "Doomed Zone"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "set_pending_delete_zone", %{"id" => to_string(zone.id)})
      render_hook(view, "confirm_delete_element", %{})

      assert Scenes.list_zones(ctx.scene.id) == []
    end
  end

  describe "pending delete + confirm_delete_element (connection)" do
    setup [:register_and_log_in_user, :setup_scene]

    test "set_pending_delete_connection + confirm deletes the connection", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "set_pending_delete_connection", %{"id" => to_string(conn_rec.id)})
      render_hook(view, "confirm_delete_element", %{})

      assert Scenes.list_connections(ctx.scene.id) == []
    end
  end

  describe "pending delete + confirm_delete_element (annotation)" do
    setup [:register_and_log_in_user, :setup_scene]

    test "set_pending_delete_annotation + confirm deletes the annotation", ctx do
      ann = annotation_fixture(ctx.scene, %{"text" => "Doomed Note"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "set_pending_delete_annotation", %{"id" => to_string(ann.id)})
      render_hook(view, "confirm_delete_element", %{})

      assert Scenes.list_annotations(ctx.scene.id) == []
    end
  end

  # -------------------------------------------------------------------
  # Zone action type / assignments / action_data handlers
  # -------------------------------------------------------------------

  describe "update_zone_action_type" do
    setup [:register_and_log_in_user, :setup_scene]

    test "changes zone action type to instruction with default data", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "instruction"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.action_type == "instruction"
      assert updated.action_data == %{"assignments" => []}
    end

    test "changes zone action type to display with default data", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "display"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.action_type == "display"
      assert updated.action_data == %{"variable_ref" => ""}
    end

    test "changes zone action type to none clears data", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Set to instruction first
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "instruction"
      })

      # Change back to none
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "none"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.action_type == "none"
      assert updated.action_data == %{}
    end

    test "no-op when zone does not exist", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Should not crash
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => "999999",
        "action-type" => "instruction"
      })
    end
  end

  describe "update_zone_assignments" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates instruction assignments for a zone", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # First set to instruction type
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "instruction"
      })

      assignments = [
        %{"variable" => "mc.health", "operator" => "set", "value" => "100"}
      ]

      render_hook(view, "update_zone_assignments", %{
        "zone-id" => to_string(zone.id),
        "assignments" => assignments
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.action_data["assignments"] == assignments
    end

    test "no-op when zone does not exist", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_assignments", %{
        "zone-id" => "999999",
        "assignments" => []
      })
    end
  end

  describe "update_zone_action_data" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates a single field in zone action_data", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # First set to display type
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "display"
      })

      render_hook(view, "update_zone_action_data", %{
        "zone-id" => to_string(zone.id),
        "field" => "variable_ref",
        "value" => "mc.jaime.health"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.action_data["variable_ref"] == "mc.jaime.health"
    end
  end

  # -------------------------------------------------------------------
  # Zone condition handlers
  # -------------------------------------------------------------------

  describe "update_zone_condition" do
    setup [:register_and_log_in_user, :setup_scene]

    test "sets zone visibility condition", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      render_hook(view, "update_zone_condition", %{
        "zone-id" => to_string(zone.id),
        "condition" => condition
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.condition["logic"] == "all"
      assert length(updated.condition["rules"]) == 1
    end

    test "handles missing condition key gracefully", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Missing zone-id and condition keys — should match fallback clause
      render_hook(view, "update_zone_condition", %{})
    end

    test "no-op for nonexistent zone", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_condition", %{
        "zone-id" => "999999",
        "condition" => %{"logic" => "all", "rules" => []}
      })
    end
  end

  describe "update_zone_condition_effect" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates zone condition effect to disable", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_condition_effect", %{
        "id" => to_string(zone.id),
        "value" => "disable"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.condition_effect == "disable"
    end

    test "updates zone condition effect to hide", ctx do
      zone = zone_fixture(ctx.scene)
      # Set to disable first
      Scenes.update_zone(zone, %{"condition_effect" => "disable"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_condition_effect", %{
        "id" => to_string(zone.id),
        "value" => "hide"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.condition_effect == "hide"
    end
  end

  # -------------------------------------------------------------------
  # Pin action type / assignments / action_data handlers
  # -------------------------------------------------------------------

  describe "update_pin_action_type" do
    setup [:register_and_log_in_user, :setup_scene]

    test "changes pin action type to instruction with default data", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "instruction"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.action_type == "instruction"
      assert updated.action_data == %{"assignments" => []}
    end

    test "changes pin action type to display", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "display"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.action_type == "display"
      assert updated.action_data == %{"variable_ref" => ""}
    end

    test "no-op when pin does not exist", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_action_type", %{
        "pin-id" => "999999",
        "action-type" => "instruction"
      })
    end
  end

  describe "update_pin_assignments" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates instruction assignments for a pin", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # First set to instruction type
      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "instruction"
      })

      assignments = [
        %{"variable" => "mc.gold", "operator" => "add", "value" => "50"}
      ]

      render_hook(view, "update_pin_assignments", %{
        "pin-id" => to_string(pin.id),
        "assignments" => assignments
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.action_data["assignments"] == assignments
    end
  end

  describe "update_pin_action_data" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates a single field in pin action_data", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Set to display type first
      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "display"
      })

      render_hook(view, "update_pin_action_data", %{
        "pin-id" => to_string(pin.id),
        "field" => "variable_ref",
        "value" => "mc.jaime.gold"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.action_data["variable_ref"] == "mc.jaime.gold"
    end
  end

  # -------------------------------------------------------------------
  # Pin condition handlers
  # -------------------------------------------------------------------

  describe "update_pin_condition" do
    setup [:register_and_log_in_user, :setup_scene]

    test "sets pin visibility condition", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      condition = %{
        "logic" => "any",
        "rules" => [
          %{
            "sheet" => "mc.jaime",
            "variable" => "alive",
            "operator" => "is_true",
            "value" => nil
          }
        ]
      }

      render_hook(view, "update_pin_condition", %{
        "pin-id" => to_string(pin.id),
        "condition" => condition
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.condition["logic"] == "any"
      assert length(updated.condition["rules"]) == 1
    end

    test "handles missing condition key gracefully", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Missing pin-id and condition keys — should match fallback clause
      render_hook(view, "update_pin_condition", %{})
    end

    test "no-op for nonexistent pin", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_condition", %{
        "pin-id" => "999999",
        "condition" => %{"logic" => "all", "rules" => []}
      })
    end
  end

  describe "update_pin_condition_effect" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates pin condition effect to disable", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_condition_effect", %{
        "id" => to_string(pin.id),
        "value" => "disable"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.condition_effect == "disable"
    end
  end

  # -------------------------------------------------------------------
  # Keyboard shortcuts: delete_selected
  # -------------------------------------------------------------------

  describe "delete_selected keyboard shortcut" do
    setup [:register_and_log_in_user, :setup_scene]

    test "deletes selected pin", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Select the pin
      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      # Delete via keyboard shortcut
      render_hook(view, "delete_selected", %{})

      assert Scenes.list_pins(ctx.scene.id) == []
    end

    test "deletes selected zone", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})
      render_hook(view, "delete_selected", %{})

      assert Scenes.list_zones(ctx.scene.id) == []
    end

    test "deletes selected connection", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "connection", "id" => conn_rec.id})
      render_hook(view, "delete_selected", %{})

      assert Scenes.list_connections(ctx.scene.id) == []
    end

    test "deletes selected annotation", ctx do
      ann = annotation_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "annotation", "id" => ann.id})
      render_hook(view, "delete_selected", %{})

      assert Scenes.list_annotations(ctx.scene.id) == []
    end

    test "no-op when nothing is selected", ctx do
      _pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Don't select anything
      render_hook(view, "delete_selected", %{})

      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end
  end

  # -------------------------------------------------------------------
  # Keyboard shortcuts: duplicate_selected
  # -------------------------------------------------------------------

  describe "duplicate_selected keyboard shortcut" do
    setup [:register_and_log_in_user, :setup_scene]

    test "duplicates selected pin", ctx do
      pin =
        pin_fixture(ctx.scene, %{
          "label" => "Original Pin",
          "position_x" => 20.0,
          "position_y" => 30.0
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})
      render_hook(view, "duplicate_selected", %{})

      pins = Scenes.list_pins(ctx.scene.id)
      assert length(pins) == 2

      copy = Enum.find(pins, &(&1.id != pin.id))
      assert copy.label == "Original Pin (copy)"
      assert copy.position_x > pin.position_x
    end

    test "duplicates selected zone", ctx do
      zone = zone_fixture(ctx.scene, %{"name" => "Forest"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})
      render_hook(view, "duplicate_selected", %{})

      zones = Scenes.list_zones(ctx.scene.id)
      assert length(zones) == 2

      copy = Enum.find(zones, &(&1.id != zone.id))
      assert copy.name == "Forest (copy)"
    end

    test "duplicates selected annotation", ctx do
      ann = annotation_fixture(ctx.scene, %{"text" => "Important Note"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "annotation", "id" => ann.id})
      render_hook(view, "duplicate_selected", %{})

      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 2

      copy = Enum.find(annotations, &(&1.id != ann.id))
      assert copy.text == "Important Note (copy)"
    end

    test "no-op when nothing is selected", ctx do
      _pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "duplicate_selected", %{})

      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end
  end

  # -------------------------------------------------------------------
  # Keyboard shortcuts: copy + paste
  # -------------------------------------------------------------------

  describe "paste_element" do
    setup [:register_and_log_in_user, :setup_scene]

    test "pastes a pin from clipboard attrs", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "paste_element", %{
        "type" => "pin",
        "attrs" => %{
          "position_x" => 40.0,
          "position_y" => 60.0,
          "label" => "Pasted Pin",
          "pin_type" => "location"
        }
      })

      pins = Scenes.list_pins(ctx.scene.id)
      assert length(pins) == 1
      [pin] = pins
      assert pin.label == "Pasted Pin"
      # Position should be shifted +5
      assert_in_delta pin.position_x, 45.0, 0.01
      assert_in_delta pin.position_y, 65.0, 0.01
    end

    test "pastes a zone from clipboard attrs", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      vertices = [
        %{"x" => 10.0, "y" => 10.0},
        %{"x" => 50.0, "y" => 10.0},
        %{"x" => 30.0, "y" => 50.0}
      ]

      render_hook(view, "paste_element", %{
        "type" => "zone",
        "attrs" => %{
          "name" => "Copied Zone",
          "vertices" => vertices
        }
      })

      zones = Scenes.list_zones(ctx.scene.id)
      assert length(zones) == 1
      [zone] = zones
      assert zone.name == "Copied Zone (paste)"
      # Vertices should be shifted +5
      [v1 | _] = zone.vertices
      assert_in_delta v1["x"], 15.0, 0.01
    end

    test "pastes an annotation from clipboard attrs", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "paste_element", %{
        "type" => "annotation",
        "attrs" => %{
          "text" => "Pasted Note",
          "position_x" => 25.0,
          "position_y" => 35.0,
          "font_size" => "lg",
          "color" => "#ff0000"
        }
      })

      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 1
      [ann] = annotations
      assert ann.text == "Pasted Note"
      assert_in_delta ann.position_x, 30.0, 0.01
      assert_in_delta ann.position_y, 40.0, 0.01
    end

    test "ignores unknown paste type", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "paste_element", %{
        "type" => "unknown",
        "attrs" => %{}
      })

      assert Scenes.list_pins(ctx.scene.id) == []
      assert Scenes.list_zones(ctx.scene.id) == []
      assert Scenes.list_annotations(ctx.scene.id) == []
    end

    test "no-op with missing params", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Fallback clause
      render_hook(view, "paste_element", %{})
    end
  end

  # -------------------------------------------------------------------
  # Sheet picker flow
  # -------------------------------------------------------------------

  describe "sheet picker" do
    setup [:register_and_log_in_user, :setup_scene]

    test "show_sheet_picker opens the picker", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      html = render_hook(view, "show_sheet_picker", %{})

      assert html =~ "sheet-picker"
    end

    test "cancel_sheet_picker closes the picker", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "show_sheet_picker", %{})
      html = render_hook(view, "cancel_sheet_picker", %{})

      refute html =~ "sheet-picker"
    end

    test "start_pin_from_sheet with invalid sheet shows error", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      html = render_hook(view, "start_pin_from_sheet", %{"sheet-id" => "999999"})

      assert html =~ "not found"
    end

    test "start_pin_from_sheet with valid sheet sets pin tool", ctx do
      sheet = sheet_fixture(ctx.project, %{name: "Knight"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "show_sheet_picker", %{})
      html = render_hook(view, "start_pin_from_sheet", %{"sheet-id" => to_string(sheet.id)})

      # Sheet picker should close
      refute html =~ "sheet-picker"
    end
  end

  # -------------------------------------------------------------------
  # Clear connection waypoints
  # -------------------------------------------------------------------

  describe "clear_connection_waypoints" do
    setup [:register_and_log_in_user, :setup_scene]

    test "clears all waypoints from a connection", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      # Set some waypoints first
      waypoints = [%{"x" => 50.0, "y" => 30.0}, %{"x" => 70.0, "y" => 60.0}]
      Scenes.update_connection_waypoints(conn_rec, %{"waypoints" => waypoints})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "clear_connection_waypoints", %{"id" => to_string(conn_rec.id)})

      updated = Scenes.get_connection!(conn_rec.id)
      assert updated.waypoints == []
    end

    test "no-op when connection does not exist", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "clear_connection_waypoints", %{"id" => "999999"})
    end
  end

  # -------------------------------------------------------------------
  # Move annotation
  # -------------------------------------------------------------------

  describe "move_annotation" do
    setup [:register_and_log_in_user, :setup_scene]

    test "moves annotation to new coordinates", ctx do
      ann = annotation_fixture(ctx.scene, %{"position_x" => 20.0, "position_y" => 30.0})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "move_annotation", %{
        "id" => to_string(ann.id),
        "position_x" => 70.0,
        "position_y" => 80.0
      })

      updated = Scenes.get_annotation!(ann.id)
      assert_in_delta updated.position_x, 70.0, 0.01
      assert_in_delta updated.position_y, 80.0, 0.01
    end

    test "no-op when annotation does not exist", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "move_annotation", %{
        "id" => "999999",
        "position_x" => 70.0,
        "position_y" => 80.0
      })
    end
  end

  # -------------------------------------------------------------------
  # Element_id alternative parameter
  # -------------------------------------------------------------------

  describe "update_pin with element_id param" do
    setup [:register_and_log_in_user, :setup_scene]

    test "update_pin accepts element_id instead of id", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Test"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin", %{
        "element_id" => to_string(pin.id),
        "field" => "label",
        "value" => "Updated via element_id"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.label == "Updated via element_id"
    end
  end

  describe "update_zone with element_id param" do
    setup [:register_and_log_in_user, :setup_scene]

    test "update_zone accepts element_id instead of id", ctx do
      zone = zone_fixture(ctx.scene, %{"name" => "Test Zone"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone", %{
        "element_id" => to_string(zone.id),
        "field" => "name",
        "value" => "Updated via element_id"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.name == "Updated via element_id"
    end
  end

  describe "update_connection with element_id param" do
    setup [:register_and_log_in_user, :setup_scene]

    test "update_connection accepts element_id instead of id", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection", %{
        "element_id" => to_string(conn_rec.id),
        "field" => "label",
        "value" => "Road"
      })

      updated = Scenes.get_connection!(conn_rec.id)
      assert updated.label == "Road"
    end
  end

  # -------------------------------------------------------------------
  # Pin deletion cascades connections
  # -------------------------------------------------------------------

  describe "delete_pin cascades to connections" do
    setup [:register_and_log_in_user, :setup_scene]

    test "deleting a pin also removes its connections", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0, "label" => "A"})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0, "label" => "B"})
      _conn = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_pin", %{"id" => to_string(pin1.id)})

      assert Scenes.list_connections(ctx.scene.id) == []
      # pin2 should remain
      assert length(Scenes.list_pins(ctx.scene.id)) == 1
    end
  end

  # -------------------------------------------------------------------
  # Nonexistent element edge cases
  # -------------------------------------------------------------------

  describe "operations on nonexistent elements" do
    setup [:register_and_log_in_user, :setup_scene]

    test "update_pin with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin", %{
        "id" => "999999",
        "field" => "label",
        "value" => "Ghost"
      })
    end

    test "update_zone with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone", %{
        "id" => "999999",
        "field" => "name",
        "value" => "Ghost"
      })
    end

    test "update_connection with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection", %{
        "id" => "999999",
        "field" => "label",
        "value" => "Ghost"
      })
    end

    test "update_annotation with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_annotation", %{
        "id" => "999999",
        "field" => "text",
        "value" => "Ghost"
      })
    end

    test "delete_pin with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_pin", %{"id" => "999999"})
    end

    test "delete_zone with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_zone", %{"id" => "999999"})
    end

    test "delete_connection with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_connection", %{"id" => "999999"})
    end

    test "delete_annotation with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "delete_annotation", %{"id" => "999999"})
    end

    test "move_pin with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "move_pin", %{
        "id" => "999999",
        "position_x" => 50.0,
        "position_y" => 50.0
      })
    end

    test "update_zone_vertices with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_vertices", %{
        "id" => "999999",
        "vertices" => [
          %{"x" => 10.0, "y" => 10.0},
          %{"x" => 50.0, "y" => 10.0},
          %{"x" => 30.0, "y" => 50.0}
        ]
      })
    end

    test "duplicate_zone with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "duplicate_zone", %{"id" => "999999"})
    end

    test "update_connection_waypoints with nonexistent id is a no-op", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection_waypoints", %{
        "id" => "999999",
        "waypoints" => [%{"x" => 50.0, "y" => 30.0}]
      })
    end
  end

  # -------------------------------------------------------------------
  # Update annotation text and font_size
  # -------------------------------------------------------------------

  describe "update_annotation fields" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates annotation text", ctx do
      ann = annotation_fixture(ctx.scene, %{"text" => "Original"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_annotation", %{
        "id" => to_string(ann.id),
        "field" => "text",
        "value" => "Updated Text"
      })

      updated = Scenes.get_annotation!(ann.id)
      assert updated.text == "Updated Text"
    end

    test "updates annotation font_size", ctx do
      ann = annotation_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_annotation", %{
        "id" => to_string(ann.id),
        "field" => "font_size",
        "value" => "lg"
      })

      updated = Scenes.get_annotation!(ann.id)
      assert updated.font_size == "lg"
    end

    test "updates annotation color", ctx do
      ann = annotation_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_annotation", %{
        "id" => to_string(ann.id),
        "field" => "color",
        "value" => "#00ff00"
      })

      updated = Scenes.get_annotation!(ann.id)
      assert updated.color == "#00ff00"
    end
  end

  # -------------------------------------------------------------------
  # Duplicate zone via direct event (non-keyboard shortcut)
  # -------------------------------------------------------------------

  describe "duplicate_zone preserves attributes" do
    setup [:register_and_log_in_user, :setup_scene]

    test "duplicated zone has shifted vertices", ctx do
      zone =
        zone_fixture(ctx.scene, %{
          "name" => "Castle",
          "fill_color" => "#ff0000",
          "vertices" => [
            %{"x" => 20.0, "y" => 20.0},
            %{"x" => 40.0, "y" => 20.0},
            %{"x" => 30.0, "y" => 40.0}
          ]
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "duplicate_zone", %{"id" => to_string(zone.id)})

      zones = Scenes.list_zones(ctx.scene.id)
      assert length(zones) == 2

      copy = Enum.find(zones, &(&1.id != zone.id))
      assert copy.name == "Castle (copy)"

      # All vertices should be shifted by +5
      [v1 | _] = copy.vertices
      assert_in_delta v1["x"], 25.0, 0.01
      assert_in_delta v1["y"], 25.0, 0.01
    end
  end

  # -------------------------------------------------------------------
  # Zone update: border_color, border_width, tooltip
  # -------------------------------------------------------------------

  describe "update_zone additional fields" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates zone border_color", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "border_color",
        "value" => "#0000ff"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.border_color == "#0000ff"
    end

    test "updates zone tooltip", ctx do
      zone = zone_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "tooltip",
        "value" => "Hover text"
      })

      updated = Scenes.get_zone!(zone.id)
      assert updated.tooltip == "Hover text"
    end
  end

  # -------------------------------------------------------------------
  # Pin update: tooltip, size, icon
  # -------------------------------------------------------------------

  describe "update_pin additional fields" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates pin tooltip", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "tooltip",
        "value" => "This is a castle"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.tooltip == "This is a castle"
    end

    test "updates pin size", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "size",
        "value" => "lg"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.size == "lg"
    end

    test "updates pin icon", ctx do
      pin = pin_fixture(ctx.scene)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "icon",
        "value" => "castle"
      })

      updated = Scenes.get_pin!(pin.id)
      assert updated.icon == "castle"
    end
  end

  # -------------------------------------------------------------------
  # Connection update: color, line_width, show_label
  # -------------------------------------------------------------------

  describe "update_connection additional fields" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates connection color", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection", %{
        "id" => to_string(conn_rec.id),
        "field" => "color",
        "value" => "#ff00ff"
      })

      updated = Scenes.get_connection!(conn_rec.id)
      assert updated.color == "#ff00ff"
    end

    test "updates connection line_width", ctx do
      pin1 = pin_fixture(ctx.scene, %{"position_x" => 10.0, "position_y" => 10.0})
      pin2 = pin_fixture(ctx.scene, %{"position_x" => 90.0, "position_y" => 90.0})
      conn_rec = connection_fixture(ctx.scene, pin1, pin2)

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_connection", %{
        "id" => to_string(conn_rec.id),
        "field" => "line_width",
        "value" => "3"
      })

      updated = Scenes.get_connection!(conn_rec.id)
      assert updated.line_width == 3
    end
  end

  # -------------------------------------------------------------------
  # Create annotation with custom params
  # -------------------------------------------------------------------

  describe "create_annotation with options" do
    setup [:register_and_log_in_user, :setup_scene]

    test "creates annotation with custom text and font_size", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "create_annotation", %{
        "position_x" => 50.0,
        "position_y" => 50.0,
        "text" => "Custom Text",
        "font_size" => "lg",
        "color" => "#123456"
      })

      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 1
      [ann] = annotations
      assert ann.text == "Custom Text"
      assert ann.font_size == "lg"
      assert ann.color == "#123456"
    end

    test "creates annotation with default text when not provided", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "create_annotation", %{
        "position_x" => 50.0,
        "position_y" => 50.0
      })

      annotations = Scenes.list_annotations(ctx.scene.id)
      assert length(annotations) == 1
      [ann] = annotations
      assert ann.text == "Note"
    end
  end

  # -------------------------------------------------------------------
  # Copy selected element (clipboard serialization)
  # -------------------------------------------------------------------

  describe "copy_selected" do
    setup [:register_and_log_in_user, :setup_scene]

    test "copies selected pin to clipboard", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Copy Me"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Select the pin first
      render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})

      # Copy it
      render_hook(view, "copy_selected", %{})

      # View should still be alive
      assert render(view) =~ "scene-canvas"
    end

    test "copies selected zone to clipboard", ctx do
      zone =
        zone_fixture(ctx.scene, %{
          "name" => "Copy Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 20.0, "y" => 10.0},
            %{"x" => 15.0, "y" => 20.0}
          ]
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "zone", "id" => zone.id})
      render_hook(view, "copy_selected", %{})

      assert render(view) =~ "scene-canvas"
    end

    test "copies selected annotation to clipboard", ctx do
      ann = annotation_fixture(ctx.scene, %{"text" => "Copy Note"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "select_element", %{"type" => "annotation", "id" => ann.id})
      render_hook(view, "copy_selected", %{})

      assert render(view) =~ "scene-canvas"
    end

    test "no-op when nothing is selected", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Copy with no selection
      render_hook(view, "copy_selected", %{})

      assert render(view) =~ "scene-canvas"
    end
  end

  # -------------------------------------------------------------------
  # Update zone action data — additional coverage
  # -------------------------------------------------------------------

  describe "update_zone_action_data — field update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates a single field in zone action_data", ctx do
      zone =
        zone_fixture(ctx.scene, %{
          "name" => "Action Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 20.0, "y" => 10.0},
            %{"x" => 15.0, "y" => 20.0}
          ]
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Set action type to display first
      render_hook(view, "update_zone_action_type", %{
        "zone-id" => to_string(zone.id),
        "action-type" => "display"
      })

      # Update the variable_ref field in action_data
      render_hook(view, "update_zone_action_data", %{
        "zone-id" => to_string(zone.id),
        "field" => "variable_ref",
        "value" => "mc.jaime.health"
      })

      updated = Scenes.get_zone(ctx.scene.id, zone.id)
      assert updated.action_data["variable_ref"] == "mc.jaime.health"
    end
  end

  # -------------------------------------------------------------------
  # Update zone condition_effect — additional
  # -------------------------------------------------------------------

  describe "update_zone_condition_effect — disable" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates zone condition_effect to disable", ctx do
      zone =
        zone_fixture(ctx.scene, %{
          "name" => "Effect Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 20.0, "y" => 10.0},
            %{"x" => 15.0, "y" => 20.0}
          ]
        })

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_zone_condition_effect", %{
        "id" => to_string(zone.id),
        "value" => "disable"
      })

      updated = Scenes.get_zone(ctx.scene.id, zone.id)
      assert updated.condition_effect == "disable"
    end
  end

  # -------------------------------------------------------------------
  # Update pin action_data — field update
  # -------------------------------------------------------------------

  describe "update_pin_action_data — field update" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates a field in pin action_data", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Data Pin"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Set action type to display
      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "display"
      })

      # Update action data field
      render_hook(view, "update_pin_action_data", %{
        "pin-id" => to_string(pin.id),
        "field" => "variable_ref",
        "value" => "mc.health"
      })

      updated = Scenes.get_pin(ctx.scene.id, pin.id)
      assert updated.action_data["variable_ref"] == "mc.health"
    end
  end

  # -------------------------------------------------------------------
  # Update pin condition_effect — additional
  # -------------------------------------------------------------------

  describe "update_pin_condition_effect — disable" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates pin condition_effect to disable", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Condition Pin"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "update_pin_condition_effect", %{
        "id" => to_string(pin.id),
        "value" => "disable"
      })

      updated = Scenes.get_pin(ctx.scene.id, pin.id)
      assert updated.condition_effect == "disable"
    end
  end

  # -------------------------------------------------------------------
  # Update pin assignments — additional
  # -------------------------------------------------------------------

  describe "update_pin_assignments — instruction" do
    setup [:register_and_log_in_user, :setup_scene]

    test "updates instruction assignments for a pin", ctx do
      pin = pin_fixture(ctx.scene, %{"label" => "Assign Pin"})

      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Set action type to instruction first
      render_hook(view, "update_pin_action_type", %{
        "pin-id" => to_string(pin.id),
        "action-type" => "instruction"
      })

      assignments = [%{"variable" => "mc.health", "operator" => "set", "value" => "100"}]

      render_hook(view, "update_pin_assignments", %{
        "pin-id" => to_string(pin.id),
        "assignments" => assignments
      })

      updated = Scenes.get_pin(ctx.scene.id, pin.id)
      assert updated.action_data["assignments"] == assignments
    end
  end
end
