defmodule Storyarn.Scenes.HealthCheckerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.HealthChecker

  @item_id "d6a3ceec-7a4c-46a4-bd43-073639a8b66c"

  test "returns no findings for a complete, internally consistent scene" do
    assert HealthChecker.check(base_snapshot()) == []
  end

  test "classifies canonical codes independently from adapters" do
    assert HealthChecker.severity_for(:missing_scene_layer) == :error
    assert HealthChecker.severity_for(:empty_action_zone) == :warning
    assert HealthChecker.severity_for(:empty_scene) == :info

    assert HealthChecker.finding(:missing_background, %{scene_id: 1}).severity == :warning
  end

  test "detects scene and layer invariants" do
    snapshot =
      base_snapshot()
      |> Map.put(:layers, [])
      |> Map.put(:scene_layer_ids, MapSet.new())
      |> put_in([:scene, :shortcut], "")
      |> put_in([:scene, :background_asset_id], nil)
      |> Map.put(:zones, [])
      |> Map.put(:pins, [])

    assert_codes(snapshot, [
      :missing_scene_layer,
      :missing_scene_shortcut,
      :missing_background,
      :empty_scene
    ])
  end

  test "detects invalid geometry, layer references, and out-of-canvas coordinates" do
    invalid_zone = %{base_zone() | id: 12, layer_id: 999, vertices: [%{"x" => 0, "y" => 0}]}
    outside_pin = %{base_pin() | id: 22, position_x: 110}

    snapshot = %{base_snapshot() | zones: [invalid_zone], pins: [outside_pin]}

    assert_codes(snapshot, [:invalid_zone_geometry, :invalid_layer_reference, :element_outside_canvas])
  end

  test "requires an icon for icon-only and combined zone labels" do
    icon = %{base_zone() | id: 13, label_mode: "icon"}
    both = %{base_zone() | id: 14, label_mode: "both"}
    text = %{base_zone() | id: 15, label_mode: "text"}

    findings = HealthChecker.check(%{base_snapshot() | zones: [icon, both, text]})

    assert Enum.any?(findings, &(&1.entity_id == 13 and &1.code == :missing_zone_label_icon))
    assert Enum.any?(findings, &(&1.entity_id == 14 and &1.code == :missing_zone_label_icon))
    refute Enum.any?(findings, &(&1.entity_id == 15 and &1.code == :missing_zone_label_icon))
  end

  test "allows freeform connections but reports malformed routes and foreign endpoints" do
    freeform = %{id: 31, from_pin_id: nil, to_pin_id: nil, waypoints: [point(10), point(20)]}
    malformed = %{id: 32, from_pin_id: nil, to_pin_id: nil, waypoints: [point(10)]}
    foreign = %{id: 33, from_pin_id: 999, to_pin_id: nil, waypoints: [point(10)]}

    snapshot = %{base_snapshot() | connections: [freeform, malformed, foreign]}
    findings = HealthChecker.check(snapshot)

    refute Enum.any?(findings, &(&1.entity_id == 31))
    assert Enum.any?(findings, &(&1.entity_id == 32 and &1.code == :invalid_connection_route))
    assert Enum.any?(findings, &(&1.entity_id == 33 and &1.code == :invalid_connection_endpoint))
  end

  test "separates invalid, empty, incomplete, stale, and mistyped action data" do
    invalid = %{base_zone() | id: 41, action_type: "display", action_data: %{}}
    empty_action = %{base_zone() | id: 42, action_type: "action", is_walkable: false, action_data: %{"assignments" => []}}

    incomplete_assignment = %{
      base_zone()
      | id: 43,
        action_type: "action",
        is_walkable: false,
        action_data: %{
          "assignments" => [
            %{"sheet" => "hero", "variable" => "health", "operator" => "add", "value" => ""}
          ]
        }
    }

    stale_display = %{
      base_zone()
      | id: 44,
        action_type: "display",
        is_walkable: false,
        action_data: %{"variable_ref" => "hero.missing", "display_mode" => "value"}
    }

    mismatch = %{
      base_zone()
      | id: 45,
        action_type: "action",
        is_walkable: false,
        action_data: %{
          "assignments" => [
            %{"sheet" => "hero", "variable" => "health", "operator" => "contains", "value" => "1"}
          ]
        }
    }

    snapshot = %{base_snapshot() | zones: [invalid, empty_action, incomplete_assignment, stale_display, mismatch]}

    assert_codes(snapshot, [
      :invalid_zone_action_configuration,
      :empty_action_zone,
      :incomplete_action_assignment,
      :stale_variable_reference,
      :variable_type_mismatch
    ])
  end

  test "validates collection identities, optional sheets, and nested authoring" do
    valid_item = %{
      "id" => @item_id,
      "sheet_id" => nil,
      "condition" => nil,
      "instruction" => %{"assignments" => []}
    }

    empty = collection_zone(51, [])
    valid = collection_zone(52, [valid_item])
    duplicate = collection_zone(53, [valid_item, valid_item])
    stale = collection_zone(54, [%{valid_item | "sheet_id" => 999}])

    snapshot = %{base_snapshot() | zones: [empty, valid, duplicate, stale]}
    findings = HealthChecker.check(snapshot)

    assert Enum.any?(findings, &(&1.entity_id == 51 and &1.code == :empty_collection))
    refute Enum.any?(findings, &(&1.entity_id == 52))
    assert Enum.any?(findings, &(&1.entity_id == 53 and &1.code == :invalid_collection_item))
    assert Enum.any?(findings, &(&1.entity_id == @item_id and &1.code == :stale_collection_sheet_reference))
  end

  test "distinguishes invalid, empty, incomplete, stale, and incompatible conditions" do
    invalid = %{base_pin() | id: 61, condition: %{"logic" => "bad", "blocks" => []}}
    empty = %{base_pin() | id: 62, condition: %{"logic" => "all", "blocks" => []}}
    incomplete = %{base_pin() | id: 63, condition: condition_rule(nil, nil, "equals", nil)}
    stale = %{base_pin() | id: 64, condition: condition_rule("hero", "missing", "equals", "x")}
    mismatch = %{base_pin() | id: 65, condition: condition_rule("hero", "health", "contains", "1")}

    snapshot = %{base_snapshot() | pins: [invalid, empty, incomplete, stale, mismatch]}

    assert_codes(snapshot, [
      :invalid_condition_structure,
      :empty_visibility_condition,
      :incomplete_condition,
      :stale_variable_reference,
      :variable_type_mismatch
    ])
  end

  test "detects stale entity and asset references only after reference context loads" do
    zone = %{base_zone() | id: 71, label_mode: "icon", label_icon_asset_id: 999}
    pin = %{base_pin() | id: 72, sheet_id: 999, flow_id: 999, icon_asset_id: 999}

    target = %{
      base_zone()
      | id: 73,
        action_type: "action",
        is_walkable: false,
        target_type: "flow",
        target_id: 999,
        action_data: %{"assignments" => []}
    }

    snapshot = %{base_snapshot() | zones: [zone, target], pins: [pin]}

    assert_codes(snapshot, [
      :invalid_asset_reference,
      :stale_pin_sheet_reference,
      :stale_pin_flow_reference,
      :stale_zone_target
    ])

    unloaded = %{snapshot | references_loaded: false}

    refute Enum.any?(HealthChecker.check(unloaded), fn finding ->
             finding.code in [
               :invalid_asset_reference,
               :stale_pin_sheet_reference,
               :stale_pin_flow_reference,
               :stale_zone_target
             ]
           end)
  end

  test "reports movement and patrol configurations ignored by exploration" do
    playable = %{base_pin() | id: 81, is_playable: true, is_leader: false, patrol_mode: "loop"}
    patrol_without_route = %{base_pin() | id: 82, is_playable: false, is_leader: false, patrol_mode: "loop"}
    branch = %{base_pin() | id: 83, is_playable: false, is_leader: false, patrol_mode: "loop"}
    target_a = %{base_pin() | id: 84, is_playable: false, is_leader: false}
    target_b = %{base_pin() | id: 85, is_playable: false, is_leader: false}

    connections = [
      %{id: 1, from_pin_id: 83, to_pin_id: 84, bidirectional: true, waypoints: []},
      %{id: 2, from_pin_id: 83, to_pin_id: 85, bidirectional: true, waypoints: []}
    ]

    snapshot =
      base_snapshot()
      |> Map.put(:pins, [playable, patrol_without_route, branch, target_a, target_b])
      |> Map.put(:connections, connections)
      |> Map.put(:scene_pin_ids, MapSet.new([81, 82, 83, 84, 85]))
      |> Map.put(:zones, [])

    assert_codes(snapshot, [
      :playable_party_without_leader,
      :patrol_on_playable_pin,
      :patrol_without_route,
      :ambiguous_patrol_route
    ])
  end

  test "checks enabled ambient flows and ignores disabled ones" do
    invalid = %{id: 91, enabled: true, flow_id: 2, trigger_type: "timed", trigger_config: %{"interval_ms" => 100}}

    missing_variable = %{
      id: 92,
      enabled: true,
      flow_id: 2,
      trigger_type: "on_event",
      trigger_config: %{"variable_ref" => ""}
    }

    stale = %{id: 93, enabled: true, flow_id: 999, trigger_type: "on_enter", trigger_config: %{}}
    disabled = %{id: 94, enabled: false, flow_id: 999, trigger_type: "bad", trigger_config: %{}}

    snapshot = %{base_snapshot() | ambient_flows: [invalid, missing_variable, stale, disabled]}
    findings = HealthChecker.check(snapshot)

    assert_codes(snapshot, [
      :invalid_ambient_trigger,
      :missing_ambient_event_variable,
      :stale_ambient_flow_reference
    ])

    refute Enum.any?(findings, &(&1.entity_id == 94))
  end

  defp assert_codes(snapshot, expected_codes) do
    codes = snapshot |> HealthChecker.check() |> Enum.map(& &1.code)

    Enum.each(expected_codes, &assert(&1 in codes, "expected #{inspect(&1)} in #{inspect(codes)}"))
  end

  defp base_snapshot do
    layer = %{id: 10, name: "Default", is_default: true}
    zone = base_zone()
    pin = base_pin()

    %{
      scene: %{id: 1, name: "World", shortcut: "world", background_asset_id: 100},
      layers: [layer],
      zones: [zone],
      pins: [pin],
      connections: [],
      annotations: [],
      ambient_flows: [],
      scene_layer_ids: MapSet.new([10]),
      scene_pin_ids: MapSet.new([20]),
      references_loaded: true,
      valid_scene_ids: MapSet.new([1, 2]),
      valid_sheet_ids: MapSet.new([1]),
      valid_flow_ids: MapSet.new([2]),
      valid_asset_ids: MapSet.new([100]),
      project_variables: [
        %{sheet_shortcut: "hero", variable_name: "health", block_type: "number"}
      ]
    }
  end

  defp base_zone do
    %{
      id: 11,
      name: "Walkable",
      layer_id: 10,
      vertices: [point(0), point(10), %{"x" => 0, "y" => 10}],
      action_type: "walkable",
      action_data: %{},
      target_type: nil,
      target_id: nil,
      label_mode: "text",
      label_icon_asset_id: nil,
      is_walkable: true,
      condition: nil
    }
  end

  defp collection_zone(id, items) do
    %{
      base_zone()
      | id: id,
        action_type: "collection",
        is_walkable: false,
        action_data: %{"items" => items}
    }
  end

  defp base_pin do
    %{
      id: 20,
      label: "Hero",
      layer_id: 10,
      position_x: 50,
      position_y: 50,
      sheet_id: nil,
      flow_id: nil,
      icon_asset_id: nil,
      condition: nil,
      is_playable: true,
      is_leader: true,
      patrol_mode: "none"
    }
  end

  defp condition_rule(sheet, variable, operator, value) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "block-1",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule-1",
              "sheet" => sheet,
              "variable" => variable,
              "operator" => operator,
              "value" => value
            }
          ]
        }
      ]
    }
  end

  defp point(value), do: %{"x" => value, "y" => value}
end
