defmodule Storyarn.Scenes.HealthChecker do
  @moduledoc """
  Produces structured authoring findings for an enriched scene snapshot.

  Errors identify persisted state that cannot be interpreted reliably,
  warnings identify valid but incomplete or contradictory authoring, and info
  findings describe valid noteworthy states. The checker is intentionally pure:
  callers provide the active project references and variable descriptors.
  """

  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Scenes.RoutePoints

  @type severity :: :error | :warning | :info
  @type finding :: %{
          required(:severity) => severity(),
          required(:code) => atom(),
          required(:scene_id) => integer() | nil,
          required(:entity_type) => String.t(),
          required(:entity_id) => integer() | String.t() | nil,
          required(:details) => map()
        }

  @max_waypoints 50
  @max_pause_ms 30_000
  @valid_action_types ~w(action walkable display collection)
  @valid_target_types ~w(flow scene)
  @valid_display_modes ~w(value label_value)
  @valid_label_modes ~w(none text icon both)
  @valid_ambient_triggers ~w(on_enter timed on_event one_shot)
  @valid_condition_operators ~w(
    equals not_equals contains starts_with ends_with is_empty
    greater_than greater_than_or_equal less_than less_than_or_equal
    is_true is_false is_nil not_contains before after
  )

  @severity_by_code %{
    invalid_ambient_trigger: :error,
    invalid_asset_reference: :error,
    invalid_collection_item: :error,
    invalid_condition_structure: :error,
    invalid_connection_endpoint: :error,
    invalid_connection_route: :error,
    invalid_layer_reference: :error,
    invalid_zone_action_configuration: :error,
    invalid_zone_geometry: :error,
    missing_scene_layer: :error,
    stale_ambient_flow_reference: :error,
    stale_collection_sheet_reference: :error,
    stale_pin_flow_reference: :error,
    stale_pin_sheet_reference: :error,
    stale_variable_reference: :error,
    stale_zone_target: :error,
    ambiguous_patrol_route: :warning,
    element_outside_canvas: :warning,
    empty_action_zone: :warning,
    incomplete_action_assignment: :warning,
    incomplete_condition: :warning,
    leader_without_walkable_area: :warning,
    missing_ambient_event_variable: :warning,
    missing_background: :warning,
    missing_default_layer: :warning,
    missing_display_variable: :warning,
    missing_scene_shortcut: :warning,
    missing_zone_label_icon: :warning,
    multiple_default_layers: :warning,
    patrol_on_playable_pin: :warning,
    patrol_without_route: :warning,
    playable_party_without_leader: :warning,
    variable_type_mismatch: :warning,
    empty_collection: :info,
    empty_scene: :info,
    empty_visibility_condition: :info
  }

  @doc "Returns the canonical severity for a scene health finding code."
  @spec severity_for(atom()) :: severity()
  def severity_for(code), do: Map.fetch!(@severity_by_code, code)

  @doc "Builds a canonical finding for the editor and aggregate dashboard adapter."
  @spec finding(atom(), map()) :: finding()
  def finding(code, attrs \\ %{}) when is_atom(code) and is_map(attrs) do
    %{
      severity: severity_for(code),
      code: code,
      scene_id: Map.get(attrs, :scene_id),
      entity_type: Map.get(attrs, :entity_type, "scene"),
      entity_id: Map.get(attrs, :entity_id),
      details: Map.get(attrs, :details, %{})
    }
  end

  @doc "Checks an enriched scene snapshot."
  @spec check(map()) :: [finding()]
  def check(%{scene: scene} = snapshot) when is_map(scene) do
    layers = Map.get(snapshot, :layers, [])
    zones = Map.get(snapshot, :zones, [])
    pins = Map.get(snapshot, :pins, [])
    connections = Map.get(snapshot, :connections, [])
    annotations = Map.get(snapshot, :annotations, [])
    ambient_flows = Map.get(snapshot, :ambient_flows, [])

    scene_findings(scene, layers, zones, pins, snapshot) ++
      layer_findings(scene, layers) ++
      Enum.flat_map(zones, &zone_findings(scene, &1, snapshot)) ++
      Enum.flat_map(pins, &pin_findings(scene, &1, snapshot, connections)) ++
      Enum.flat_map(connections, &connection_findings(scene, &1, snapshot)) ++
      Enum.flat_map(annotations, &annotation_findings(scene, &1, snapshot)) ++
      Enum.flat_map(ambient_flows, &ambient_flow_findings(scene, &1, snapshot))
  end

  def check(_snapshot), do: []

  defp scene_findings(scene, layers, zones, pins, snapshot) do
    background_id = field(scene, :background_asset_id)

    []
    |> maybe_add(layers == [], scene_finding(scene, :missing_scene_layer))
    |> maybe_add(blank?(field(scene, :shortcut)), scene_finding(scene, :missing_scene_shortcut))
    |> maybe_add(is_nil(background_id), scene_finding(scene, :missing_background))
    |> maybe_add(
      references_loaded?(snapshot) and not is_nil(background_id) and
        not active_id?(snapshot, :valid_asset_ids, background_id),
      scene_finding(scene, :invalid_asset_reference, %{asset_role: "background"})
    )
    |> maybe_add(zones == [] and pins == [], scene_finding(scene, :empty_scene))
    |> Kernel.++(playable_scene_findings(scene, pins, zones))
  end

  defp layer_findings(_scene, []), do: []

  defp layer_findings(scene, layers) do
    default_count = Enum.count(layers, &(field(&1, :is_default, false) == true))

    []
    |> maybe_add(default_count == 0, scene_finding(scene, :missing_default_layer))
    |> maybe_add(default_count > 1, scene_finding(scene, :multiple_default_layers, %{count: default_count}))
  end

  defp playable_scene_findings(scene, pins, zones) do
    playable? = Enum.any?(pins, &(field(&1, :is_playable, false) == true))
    leader? = Enum.any?(pins, &(field(&1, :is_leader, false) == true))
    walkable? = Enum.any?(zones, &walkable_zone?/1)

    []
    |> maybe_add(playable? and not leader?, scene_finding(scene, :playable_party_without_leader))
    |> maybe_add(leader? and not walkable?, scene_finding(scene, :leader_without_walkable_area))
  end

  defp zone_findings(scene, zone, snapshot) do
    geometry_findings(scene, zone) ++
      element_layer_findings(scene, zone, "zone", snapshot) ++
      element_asset_findings(scene, zone, snapshot) ++
      zone_action_findings(scene, zone, snapshot) ++
      condition_findings(scene, zone, "zone", field(zone, :condition), snapshot)
  end

  defp geometry_findings(scene, zone) do
    vertices = field(zone, :vertices)
    invalid? = not is_list(vertices) or length(vertices) < 3 or not Enum.all?(vertices, &valid_point?/1)

    []
    |> maybe_add(invalid?, entity_finding(scene, zone, "zone", :invalid_zone_geometry))
    |> maybe_add(
      not invalid? and Enum.any?(vertices, &outside_canvas?/1),
      entity_finding(scene, zone, "zone", :element_outside_canvas, %{location: "vertex"})
    )
  end

  defp element_asset_findings(scene, zone, snapshot) do
    asset_id = field(zone, :label_icon_asset_id)

    []
    |> maybe_add(
      references_loaded?(snapshot) and not is_nil(asset_id) and
        not active_id?(snapshot, :valid_asset_ids, asset_id),
      entity_finding(scene, zone, "zone", :invalid_asset_reference, %{asset_role: "label_icon"})
    )
    |> maybe_add(
      field(zone, :label_mode) in ["icon", "both"] and is_nil(asset_id),
      entity_finding(scene, zone, "zone", :missing_zone_label_icon)
    )
  end

  defp zone_action_findings(scene, zone, snapshot) do
    action_type = field(zone, :action_type)
    action_data = field(zone, :action_data, %{})
    target_type = field(zone, :target_type)
    target_id = field(zone, :target_id)
    configuration_valid? = valid_zone_action_configuration?(zone)

    []
    |> maybe_add(
      not configuration_valid?,
      entity_finding(scene, zone, "zone", :invalid_zone_action_configuration)
    )
    |> maybe_add(
      configuration_valid? and action_type == "action" and
        not complete_target?(target_type, target_id) and
        not Instruction.has_assignments?(Map.get(action_data, "assignments")),
      entity_finding(scene, zone, "zone", :empty_action_zone)
    )
    |> Kernel.++(zone_target_findings(scene, zone, snapshot, configuration_valid?))
    |> Kernel.++(zone_data_findings(scene, zone, snapshot, configuration_valid?))
  end

  defp valid_zone_action_configuration?(zone) do
    action_type = field(zone, :action_type)
    action_data = field(zone, :action_data, %{})
    target_type = field(zone, :target_type)
    target_id = field(zone, :target_id)
    label_mode = field(zone, :label_mode, "text")
    is_walkable = field(zone, :is_walkable, false)

    action_type in @valid_action_types and
      label_mode in @valid_label_modes and
      valid_target_pair?(target_type, target_id) and
      valid_action_target?(action_type, target_type, target_id) and
      valid_walkable_pair?(action_type, is_walkable) and
      valid_action_data?(action_type, action_data) and
      not (action_type == "display" and label_mode == "none")
  end

  defp valid_target_pair?(nil, nil), do: true
  defp valid_target_pair?(type, id), do: type in @valid_target_types and present_id?(id)

  defp valid_action_target?("action", _target_type, _target_id), do: true
  defp valid_action_target?(_action_type, nil, nil), do: true
  defp valid_action_target?(_action_type, _target_type, _target_id), do: false

  defp valid_walkable_pair?("walkable", true), do: true
  defp valid_walkable_pair?("walkable", _), do: false
  defp valid_walkable_pair?(_, false), do: true
  defp valid_walkable_pair?(_, _), do: false

  defp valid_action_data?("action", %{"assignments" => assignments}), do: is_list(assignments)

  defp valid_action_data?("display", %{"variable_ref" => ref} = data) do
    is_binary(ref) and Map.get(data, "display_mode", "value") in @valid_display_modes
  end

  defp valid_action_data?("collection", %{"items" => items}), do: is_list(items)
  defp valid_action_data?("walkable", data), do: is_map(data)
  defp valid_action_data?(_, _), do: false

  defp zone_target_findings(_scene, _zone, _snapshot, false), do: []

  defp zone_target_findings(scene, zone, snapshot, true) do
    target_type = field(zone, :target_type)
    target_id = field(zone, :target_id)

    stale? =
      references_loaded?(snapshot) and complete_target?(target_type, target_id) and
        case target_type do
          "flow" -> not active_id?(snapshot, :valid_flow_ids, target_id)
          "scene" -> not active_id?(snapshot, :valid_scene_ids, target_id)
          _ -> false
        end

    maybe_list(stale?, entity_finding(scene, zone, "zone", :stale_zone_target, %{target_type: target_type}))
  end

  defp zone_data_findings(_scene, _zone, _snapshot, false), do: []

  defp zone_data_findings(scene, zone, snapshot, true) do
    action_type = field(zone, :action_type)
    data = field(zone, :action_data, %{})

    case action_type do
      "action" -> assignment_findings(scene, zone, "zone", data["assignments"], snapshot)
      "display" -> display_findings(scene, zone, data["variable_ref"], snapshot)
      "collection" -> collection_findings(scene, zone, data["items"], snapshot)
      _ -> []
    end
  end

  defp display_findings(scene, zone, variable_ref, snapshot) do
    []
    |> maybe_add(blank?(variable_ref), entity_finding(scene, zone, "zone", :missing_display_variable))
    |> maybe_add(
      references_loaded?(snapshot) and not blank?(variable_ref) and
        not Map.has_key?(variable_types(snapshot), variable_ref),
      entity_finding(scene, zone, "zone", :stale_variable_reference, %{reference: variable_ref})
    )
  end

  defp collection_findings(scene, zone, items, snapshot) do
    invalid? = invalid_collection_items?(items)

    []
    |> maybe_add(invalid?, entity_finding(scene, zone, "zone", :invalid_collection_item))
    |> maybe_add(not invalid? and items == [], entity_finding(scene, zone, "zone", :empty_collection))
    |> Kernel.++(
      if invalid? do
        []
      else
        Enum.flat_map(items, &collection_item_findings(scene, zone, &1, snapshot))
      end
    )
  end

  defp invalid_collection_items?(items) when not is_list(items), do: true

  defp invalid_collection_items?(items) do
    ids = Enum.map(items, &field(&1, :id))

    Enum.any?(items, &(not is_map(&1))) or
      Enum.any?(ids, &(not valid_uuid?(&1))) or
      length(ids) != length(Enum.uniq(ids))
  end

  defp collection_item_findings(scene, zone, item, snapshot) do
    item_id = field(item, :id)
    sheet_id = normalize_id(field(item, :sheet_id))
    assignments = item |> field(:instruction, %{}) |> field(:assignments, [])
    attrs = %{entity_id: item_id, details: %{zone_id: field(zone, :id), item_id: item_id}}

    []
    |> maybe_add(
      references_loaded?(snapshot) and not is_nil(sheet_id) and
        not active_id?(snapshot, :valid_sheet_ids, sheet_id),
      finding(
        :stale_collection_sheet_reference,
        Map.merge(attrs, %{scene_id: field(scene, :id), entity_type: "collection_item"})
      )
    )
    |> Kernel.++(condition_findings(scene, item, "collection_item", field(item, :condition), snapshot, attrs.details))
    |> Kernel.++(assignment_findings(scene, item, "collection_item", assignments, snapshot, attrs.details))
  end

  defp pin_findings(scene, pin, snapshot, connections) do
    layer_findings = element_layer_findings(scene, pin, "pin", snapshot)
    asset_findings = pin_asset_findings(scene, pin, snapshot)
    reference_findings = pin_reference_findings(scene, pin, snapshot)
    patrol_findings = patrol_findings(scene, pin, connections)

    layer_findings ++
      asset_findings ++
      reference_findings ++
      patrol_findings ++
      point_position_findings(scene, pin, "pin") ++
      condition_findings(scene, pin, "pin", field(pin, :condition), snapshot)
  end

  defp pin_asset_findings(scene, pin, snapshot) do
    asset_id = field(pin, :icon_asset_id)

    maybe_list(
      references_loaded?(snapshot) and not is_nil(asset_id) and
        not active_id?(snapshot, :valid_asset_ids, asset_id),
      entity_finding(scene, pin, "pin", :invalid_asset_reference, %{asset_role: "pin_icon"})
    )
  end

  defp pin_reference_findings(scene, pin, snapshot) do
    sheet_id = field(pin, :sheet_id)
    flow_id = field(pin, :flow_id)

    []
    |> maybe_add(
      references_loaded?(snapshot) and not is_nil(sheet_id) and
        not active_id?(snapshot, :valid_sheet_ids, sheet_id),
      entity_finding(scene, pin, "pin", :stale_pin_sheet_reference)
    )
    |> maybe_add(
      references_loaded?(snapshot) and not is_nil(flow_id) and
        not active_id?(snapshot, :valid_flow_ids, flow_id),
      entity_finding(scene, pin, "pin", :stale_pin_flow_reference)
    )
  end

  defp patrol_findings(scene, pin, connections) do
    patrol? = field(pin, :patrol_mode, "none") not in [nil, "none"]
    playable? = field(pin, :is_playable, false) == true
    {route_count, ambiguous?} = patrol_route_facts(field(pin, :id), connections)

    []
    |> maybe_add(patrol? and playable?, entity_finding(scene, pin, "pin", :patrol_on_playable_pin))
    |> maybe_add(
      patrol? and not playable? and route_count < 2,
      entity_finding(scene, pin, "pin", :patrol_without_route)
    )
    |> maybe_add(
      patrol? and not playable? and route_count >= 2 and ambiguous?,
      entity_finding(scene, pin, "pin", :ambiguous_patrol_route)
    )
  end

  defp patrol_route_facts(pin_id, connections) do
    do_patrol_route_facts(pin_id, MapSet.new([pin_id]), connections, 1, false)
  end

  defp do_patrol_route_facts(nil, _visited, _connections, count, ambiguous?), do: {count, ambiguous?}

  defp do_patrol_route_facts(pin_id, visited, connections, count, ambiguous?) do
    next_connections =
      connections
      |> Enum.filter(&traversable_from?(&1, pin_id, visited))
      |> Enum.sort_by(&field(&1, :id, 0))

    case next_connections do
      [] ->
        {count, ambiguous?}

      [connection | _] ->
        waypoints = field(connection, :waypoints, []) || []
        target_id = traversal_target(connection, pin_id)
        next_count = count + length(waypoints) + if(is_nil(target_id), do: 0, else: 1)
        next_visited = if is_nil(target_id), do: visited, else: MapSet.put(visited, target_id)

        do_patrol_route_facts(
          target_id,
          next_visited,
          connections,
          next_count,
          ambiguous? or length(next_connections) > 1
        )
    end
  end

  defp traversable_from?(connection, pin_id, visited) do
    from_id = field(connection, :from_pin_id)
    to_id = field(connection, :to_pin_id)
    bidirectional? = field(connection, :bidirectional, true) == true

    (from_id == pin_id and unvisited_target?(to_id, visited)) or
      (bidirectional? and to_id == pin_id and unvisited_target?(from_id, visited))
  end

  defp traversal_target(connection, pin_id) do
    if field(connection, :from_pin_id) == pin_id,
      do: field(connection, :to_pin_id),
      else: field(connection, :from_pin_id)
  end

  defp unvisited_target?(nil, _visited), do: true
  defp unvisited_target?(target_id, visited), do: not MapSet.member?(visited, target_id)

  defp connection_findings(scene, connection, snapshot) do
    from_id = field(connection, :from_pin_id)
    to_id = field(connection, :to_pin_id)
    waypoints = field(connection, :waypoints, [])
    invalid_route? = invalid_connection_route?(connection, from_id, to_id, waypoints)
    invalid_endpoint? = invalid_connection_endpoint?(snapshot, from_id, to_id)

    []
    |> maybe_add(invalid_route?, entity_finding(scene, connection, "connection", :invalid_connection_route))
    |> maybe_add(
      invalid_endpoint?,
      entity_finding(scene, connection, "connection", :invalid_connection_endpoint)
    )
    |> maybe_add(
      not invalid_route? and Enum.any?(waypoints, &outside_canvas?/1),
      entity_finding(scene, connection, "connection", :element_outside_canvas, %{location: "waypoint"})
    )
  end

  defp invalid_connection_route?(connection, from_id, to_id, waypoints) do
    not is_list(waypoints) or length(waypoints) > @max_waypoints or
      (is_list(waypoints) and not Enum.all?(waypoints, &RoutePoints.valid_waypoint?/1)) or
      (is_list(waypoints) and not RoutePoints.enough_points?(from_id, to_id, waypoints)) or
      not valid_endpoint_pause?(field(connection, :from_pause_ms)) or
      not valid_endpoint_pause?(field(connection, :to_pause_ms))
  end

  defp invalid_connection_endpoint?(snapshot, from_id, to_id) do
    pin_ids = Map.get(snapshot, :scene_pin_ids, MapSet.new())

    (not is_nil(from_id) and not MapSet.member?(pin_ids, from_id)) or
      (not is_nil(to_id) and not MapSet.member?(pin_ids, to_id)) or
      (not is_nil(from_id) and from_id == to_id)
  end

  defp annotation_findings(scene, annotation, snapshot) do
    element_layer_findings(scene, annotation, "annotation", snapshot) ++
      point_position_findings(scene, annotation, "annotation")
  end

  defp point_position_findings(scene, entity, entity_type) do
    point = %{x: field(entity, :position_x), y: field(entity, :position_y)}

    maybe_list(
      valid_point?(point) and outside_canvas?(point),
      entity_finding(scene, entity, entity_type, :element_outside_canvas, %{location: "position"})
    )
  end

  defp element_layer_findings(scene, entity, entity_type, snapshot) do
    layer_id = field(entity, :layer_id)

    maybe_list(
      not is_nil(layer_id) and not MapSet.member?(Map.get(snapshot, :scene_layer_ids, MapSet.new()), layer_id),
      entity_finding(scene, entity, entity_type, :invalid_layer_reference)
    )
  end

  defp ambient_flow_findings(scene, ambient_flow, snapshot) do
    if field(ambient_flow, :enabled, true) == false do
      []
    else
      enabled_ambient_flow_findings(scene, ambient_flow, snapshot)
    end
  end

  defp enabled_ambient_flow_findings(scene, ambient_flow, snapshot) do
    flow_id = field(ambient_flow, :flow_id)
    trigger_type = field(ambient_flow, :trigger_type)
    trigger_config = field(ambient_flow, :trigger_config, %{})
    trigger_valid? = valid_ambient_trigger?(trigger_type, trigger_config)
    variable_ref = if is_map(trigger_config), do: field(trigger_config, :variable_ref)

    []
    |> maybe_add(
      stale_ambient_flow?(snapshot, flow_id),
      entity_finding(scene, ambient_flow, "ambient_flow", :stale_ambient_flow_reference)
    )
    |> maybe_add(
      not trigger_valid?,
      entity_finding(scene, ambient_flow, "ambient_flow", :invalid_ambient_trigger)
    )
    |> maybe_add(
      missing_ambient_event_variable?(trigger_type, trigger_valid?, variable_ref),
      entity_finding(scene, ambient_flow, "ambient_flow", :missing_ambient_event_variable)
    )
    |> maybe_add(
      stale_ambient_event_variable?(snapshot, trigger_type, trigger_valid?, variable_ref),
      entity_finding(scene, ambient_flow, "ambient_flow", :stale_variable_reference, %{
        reference: variable_ref
      })
    )
  end

  defp stale_ambient_flow?(snapshot, flow_id) do
    references_loaded?(snapshot) and
      (is_nil(flow_id) or not active_id?(snapshot, :valid_flow_ids, flow_id))
  end

  defp missing_ambient_event_variable?(trigger_type, trigger_valid?, variable_ref) do
    trigger_valid? and trigger_type == "on_event" and blank?(variable_ref)
  end

  defp stale_ambient_event_variable?(snapshot, trigger_type, trigger_valid?, variable_ref) do
    trigger_valid? and trigger_type == "on_event" and not blank?(variable_ref) and
      references_loaded?(snapshot) and not Map.has_key?(variable_types(snapshot), variable_ref)
  end

  defp valid_ambient_trigger?(trigger_type, config) when trigger_type in @valid_ambient_triggers and is_map(config) do
    case trigger_type do
      "timed" -> is_integer(field(config, :interval_ms)) and field(config, :interval_ms) >= 1_000
      "on_event" -> is_binary(field(config, :variable_ref, ""))
      _ -> config == %{}
    end
  end

  defp valid_ambient_trigger?(_, _), do: false

  defp assignment_findings(scene, entity, entity_type, assignments, snapshot, extra_details \\ %{}) do
    assignments = if is_list(assignments), do: assignments, else: []
    incomplete? = assignments != [] and Enum.any?(assignments, &(not Instruction.complete_assignment?(&1)))

    stale_refs =
      if references_loaded?(snapshot), do: stale_assignment_refs(assignments, variable_types(snapshot)), else: []

    type_warning? = Instruction.has_type_warnings?(assignments, Map.get(snapshot, :project_variables, []))

    []
    |> maybe_add(
      incomplete?,
      entity_finding(scene, entity, entity_type, :incomplete_action_assignment, extra_details)
    )
    |> maybe_add(
      stale_refs != [],
      entity_finding(
        scene,
        entity,
        entity_type,
        :stale_variable_reference,
        Map.put(extra_details, :references, stale_refs)
      )
    )
    |> maybe_add(
      type_warning?,
      entity_finding(scene, entity, entity_type, :variable_type_mismatch, extra_details)
    )
  end

  defp stale_assignment_refs(assignments, types) do
    assignments
    |> Enum.flat_map(fn assignment ->
      target = variable_ref(field(assignment, :sheet), field(assignment, :variable))

      source =
        if field(assignment, :value_type) == "variable_ref" do
          variable_ref(field(assignment, :value_sheet), field(assignment, :value))
        end

      Enum.reject([target, source], &(is_nil(&1) or Map.has_key?(types, &1)))
    end)
    |> Enum.uniq()
  end

  defp condition_findings(scene, entity, entity_type, condition, snapshot, extra_details \\ %{}) do
    rules = Condition.extract_all_rules(condition)

    cond do
      is_nil(condition) ->
        []

      match?({:error, _}, Condition.validate(condition)) ->
        [entity_finding(scene, entity, entity_type, :invalid_condition_structure, extra_details)]

      rules == [] ->
        [entity_finding(scene, entity, entity_type, :empty_visibility_condition, extra_details)]

      true ->
        incomplete? = Enum.any?(rules, &(not complete_condition_rule?(&1)))

        stale_refs =
          if references_loaded?(snapshot),
            do: stale_condition_refs(rules, variable_types(snapshot)),
            else: []

        type_mismatch? = condition_type_mismatch?(rules, variable_types(snapshot))

        []
        |> maybe_add(
          incomplete?,
          entity_finding(scene, entity, entity_type, :incomplete_condition, extra_details)
        )
        |> maybe_add(
          stale_refs != [],
          entity_finding(
            scene,
            entity,
            entity_type,
            :stale_variable_reference,
            Map.put(extra_details, :references, stale_refs)
          )
        )
        |> maybe_add(
          type_mismatch?,
          entity_finding(scene, entity, entity_type, :variable_type_mismatch, extra_details)
        )
    end
  end

  defp complete_condition_rule?(rule) do
    ref = variable_ref(field(rule, :sheet), field(rule, :variable))
    operator = field(rule, :operator)

    not is_nil(ref) and operator in @valid_condition_operators and
      (not Condition.operator_requires_value?(operator) or not blank?(field(rule, :value)))
  end

  defp stale_condition_refs(rules, types) do
    rules
    |> Enum.map(&variable_ref(field(&1, :sheet), field(&1, :variable)))
    |> Enum.reject(&(is_nil(&1) or Map.has_key?(types, &1)))
    |> Enum.uniq()
  end

  defp condition_type_mismatch?(rules, types) do
    Enum.any?(rules, fn rule ->
      ref = variable_ref(field(rule, :sheet), field(rule, :variable))
      operator = field(rule, :operator)

      case Map.get(types, ref) do
        nil -> false
        type -> operator in @valid_condition_operators and operator not in Condition.operators_for_type(type)
      end
    end)
  end

  defp variable_types(snapshot) do
    Map.get_lazy(snapshot, :variable_types, fn ->
      snapshot
      |> Map.get(:project_variables, [])
      |> Map.new(fn variable ->
        {variable_ref(field(variable, :sheet_shortcut), field(variable, :variable_name)), field(variable, :block_type)}
      end)
      |> Map.delete(nil)
    end)
  end

  defp references_loaded?(snapshot), do: Map.get(snapshot, :references_loaded, false) == true

  defp active_id?(snapshot, key, id) do
    MapSet.member?(Map.get(snapshot, key, MapSet.new()), normalize_id(id))
  end

  defp walkable_zone?(zone) do
    field(zone, :action_type) == "walkable" and field(zone, :is_walkable, false) == true
  end

  defp complete_target?(type, id), do: type in @valid_target_types and present_id?(id)

  defp valid_point?(point) when is_map(point) do
    is_number(field(point, :x)) and is_number(field(point, :y))
  end

  defp valid_point?(_), do: false

  defp outside_canvas?(point) do
    x = field(point, :x)
    y = field(point, :y)
    is_number(x) and is_number(y) and (x < 0 or x > 100 or y < 0 or y > 100)
  end

  defp valid_endpoint_pause?(nil), do: true
  defp valid_endpoint_pause?(value), do: is_integer(value) and value >= 0 and value <= @max_pause_ms

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_), do: false

  defp variable_ref(sheet, variable) when is_binary(sheet) and is_binary(variable) do
    if blank?(sheet) or blank?(variable), do: nil, else: "#{sheet}.#{variable}"
  end

  defp variable_ref(_, _), do: nil

  defp present_id?(id), do: not is_nil(normalize_id(id))

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp scene_finding(scene, code, details \\ %{}) do
    finding(code, %{scene_id: field(scene, :id), details: details})
  end

  defp entity_finding(scene, entity, entity_type, code, details \\ %{}) do
    finding(code, %{
      scene_id: field(scene, :id),
      entity_type: entity_type,
      entity_id: field(entity, :id),
      details: details
    })
  end

  defp maybe_add(findings, true, finding), do: findings ++ [finding]
  defp maybe_add(findings, false, _finding), do: findings

  defp maybe_list(true, finding), do: [finding]
  defp maybe_list(false, _finding), do: []

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp field(map, key, default \\ nil)
  defp field(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp field(_map, _key, default), do: default
end
