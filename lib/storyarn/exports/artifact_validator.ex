defmodule Storyarn.Exports.ArtifactValidator do
  @moduledoc """
  Validates whether selected project data can be represented safely in the
  target export format.

  This deliberately does not duplicate authoring-health rules. It checks the
  runtime identifiers, live references, and generated expressions that form
  the exported artifact's contract.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.ExpressionTranspiler
  alias Storyarn.Exports.ExpressionTranspiler.Helpers, as: ExpressionHelpers
  alias Storyarn.Exports.Serializers.FlowControlResolver
  alias Storyarn.Exports.Serializers.GraphTraversal
  alias Storyarn.Exports.Serializers.Helpers, as: SerializerHelpers
  alias Storyarn.Exports.Serializers.Yarn
  alias Storyarn.Projects.FlowCondition
  alias Storyarn.Projects.FlowInstruction
  alias Storyarn.Projects.FlowNodeConnectionRules
  alias Storyarn.Projects.FlowReadModel
  alias Storyarn.Projects.LocalizationRuntimeKey, as: RuntimeKey
  alias Storyarn.References
  alias Storyarn.Shared.StringUtils
  alias Storyarn.Sheets

  @stale_variable_blocking_formats [:ink]
  @control_reference_blocking_formats [:ink, :yarn, :godot]
  @normalized_identifier_formats [:ink, :yarn, :godot, :unreal]
  @hub_identifier_formats [:ink, :yarn, :godot]
  @runtime_id_rules [
    :invalid_dialogue_runtime_id,
    :invalid_response_runtime_id,
    :duplicate_dialogue_runtime_id
  ]
  @blocking_runtime_id_rules [
    :duplicate_response_runtime_id,
    :invalid_dialogue_data,
    :invalid_response_data
  ]
  @required_identifier_rules [
    :invalid_flow_identifier,
    :invalid_sheet_identifier
  ]
  @normalized_entity_collision_rules [
    :flow_identifier_collision,
    :sheet_identifier_collision
  ]
  @flattened_variable_identifier_formats [:ink, :yarn, :unreal]
  @control_reference_rules [
    :missing_jump_target,
    :missing_subflow_reference,
    :missing_exit_flow_reference,
    :stale_jump_target,
    :stale_subflow_reference,
    :stale_exit_flow_reference
  ]
  @linear_formats [:ink, :yarn, :godot]

  @type validation_context :: %{
          optional(:active_flows) => [map()],
          optional(:declared_variables) => [map()],
          optional(:referenceable_variables) => [map()],
          optional(:stale_node_variable_refs_by_flow) => %{
            integer() => %{integer() => MapSet.t(String.t())}
          },
          optional(:stale_node_ids_by_flow) => %{integer() => MapSet.t(integer())},
          optional(:effective_flow_result) => {[map()], [map()]}
        }

  @spec findings(pos_integer(), ExportOptions.t(), [map()], [map()]) :: [map()]
  def findings(project_id, %ExportOptions{} = options, flows, sheets) do
    findings(project_id, options, flows, sheets, %{})
  end

  @spec findings(pos_integer(), ExportOptions.t(), [map()], [map()], validation_context()) ::
          [map()]
  def findings(project_id, %ExportOptions{} = options, flows, sheets, validation_context)
      when is_map(validation_context) do
    declared_variables =
      Map.get_lazy(
        validation_context,
        :declared_variables,
        fn -> declared_variables(project_id, sheets) end
      )

    referenceable_variables =
      Map.get_lazy(
        validation_context,
        :referenceable_variables,
        fn -> referenceable_variables(project_id, flows) end
      )

    {artifact_flows, reachability_findings} =
      Map.get_lazy(
        validation_context,
        :effective_flow_result,
        fn -> effective_flows(options.format, flows) end
      )

    stale_node_variable_refs_by_flow =
      Map.get_lazy(
        validation_context,
        :stale_node_variable_refs_by_flow,
        fn -> stale_node_variable_refs_by_flow(artifact_flows) end
      )

    active_flows =
      active_flows(project_id, artifact_flows, validation_context)

    runtime_identifier_findings(options, artifact_flows, sheets) ++
      variable_identifier_findings(options.format, declared_variables) ++
      identifier_collision_findings(options.format, artifact_flows, sheets, declared_variables) ++
      dialogue_runtime_id_findings(options.format, artifact_flows) ++
      yarn_line_id_findings(options.format, artifact_flows) ++
      control_reference_findings(options.format, artifact_flows, active_flows) ++
      variable_reference_findings(
        options.format,
        artifact_flows,
        referenceable_variables,
        stale_node_variable_refs_by_flow
      ) ++
      variable_type_mismatch_findings(
        options.format,
        artifact_flows,
        referenceable_variables
      ) ++
      expression_findings(options.format, artifact_flows) ++ reachability_findings
  end

  @doc false
  @spec effective_flows(atom(), [map()]) :: {[map()], [map()]}
  def effective_flows(format, flows) when format in @linear_formats do
    Enum.map_reduce(flows, [], fn flow, findings ->
      flow = normalize_artifact_flow(flow)
      entry = Enum.find(flow.nodes, &(&1.type == "entry"))

      if is_nil(entry) do
        {flow, findings}
      else
        reachable_node_ids =
          GraphTraversal.reachable_node_ids(flow, graph_traversal_options(format))

        unreachable_findings =
          flow.nodes
          |> Enum.filter(
            &(not MapSet.member?(reachable_node_ids, &1.id) and
                FlowNodeConnectionRules.can_be_unreachable?(&1.type))
          )
          |> Enum.map(&unreachable_node_finding(format, flow, &1))

        {restrict_flow_to_nodes(flow, reachable_node_ids), findings ++ unreachable_findings}
      end
    end)
  end

  def effective_flows(_format, flows), do: {Enum.map(flows, &normalize_artifact_flow/1), []}

  defp graph_traversal_options(:yarn), do: [split_reconvergences: true]
  defp graph_traversal_options(_format), do: []

  defp normalize_artifact_flow(flow) do
    nodes =
      flow.nodes
      |> list_or_empty()
      |> Enum.map(&Map.put(&1, :data, Map.get(&1, :data) || %{}))

    %{flow | nodes: nodes, connections: list_or_empty(flow.connections)}
  end

  defp restrict_flow_to_nodes(flow, node_ids) do
    nodes = flow.nodes |> list_or_empty() |> Enum.filter(&MapSet.member?(node_ids, &1.id))

    connections =
      flow.connections
      |> list_or_empty()
      |> Enum.filter(
        &(MapSet.member?(node_ids, &1.source_node_id) and
            MapSet.member?(node_ids, &1.target_node_id))
      )

    %{flow | nodes: nodes, connections: connections}
  end

  defp unreachable_node_finding(format, flow, node) do
    node_finding(
      :warning,
      :unreachable_node,
      flow,
      node,
      dgettext(
        "projects",
        ~s("%{node}" in flow "%{flow}" is not reachable from Entry and will not be included in the %{format} export),
        node: FlowReadModel.node_label(node),
        flow: flow.name,
        format: format_label(format)
      ),
      format: format
    )
  end

  defp runtime_identifier_findings(options, flows, sheets) do
    flow_findings =
      Enum.flat_map(flows, fn flow ->
        with false <- valid_identifier?(flow.shortcut, options.format),
             level when level in [:error, :warning] <-
               integrity_level(:invalid_flow_identifier, options.format) do
          [
            %{
              level: level,
              rule: :invalid_flow_identifier,
              format: options.format,
              flow_id: flow.id,
              flow_name: flow.name,
              entity_type: "flow",
              entity_id: flow.id,
              entity_label: flow.name,
              message:
                dgettext(
                  "projects",
                  "Flow \"%{name}\" needs a valid shortcut for the %{format} export",
                  name: flow.name,
                  format: format_label(options.format)
                )
            }
          ]
        else
          _valid_or_ignored -> []
        end
      end)

    sheet_findings =
      Enum.flat_map(sheets, fn sheet ->
        with false <- valid_sheet_identifier?(sheet.shortcut, options.format),
             level when level in [:error, :warning] <-
               integrity_level(:invalid_sheet_identifier, options.format) do
          [
            %{
              level: level,
              rule: :invalid_sheet_identifier,
              format: options.format,
              sheet_id: sheet.id,
              sheet_name: sheet.name,
              entity_type: "sheet",
              entity_id: sheet.id,
              entity_label: sheet.name,
              message:
                dgettext(
                  "projects",
                  "Sheet \"%{name}\" needs a valid shortcut for the %{format} export",
                  name: sheet.name,
                  format: format_label(options.format)
                )
            }
          ]
        else
          _valid_or_ignored -> []
        end
      end)

    flow_findings ++ sheet_findings
  end

  defp valid_identifier?(value, _format) when not is_binary(value) or value == "", do: false

  defp valid_identifier?(value, format), do: format_identifier_valid?(value, format)

  defp valid_sheet_identifier?(value, _format) when not is_binary(value) or value == "", do: false

  defp valid_sheet_identifier?(value, :unreal) do
    value
    |> String.split(".")
    |> Enum.all?(&Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, &1))
  end

  defp valid_sheet_identifier?(value, format), do: format_identifier_valid?(value, format)

  defp format_identifier_valid?(shortcut, format) when format in @normalized_identifier_formats do
    identifier = SerializerHelpers.shortcut_to_identifier(shortcut)
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, identifier)
  end

  defp format_identifier_valid?(shortcut, :articy) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, shortcut)
  end

  defp format_identifier_valid?(shortcut, _format), do: shortcut != ""

  defp identifier_collision_findings(format, flows, sheets, variables) do
    flow_identifier_collision_findings(format, flows) ++
      sheet_identifier_collision_findings(format, sheets) ++
      hub_identifier_findings(format, flows) ++
      yarn_node_identifier_collision_findings(format, flows) ++
      variable_identifier_collision_findings(format, variables)
  end

  defp variable_identifier_findings(format, variables) do
    Enum.flat_map(variables, fn variable ->
      if valid_variable_identifier?(variable, format) do
        []
      else
        [
          %{
            level: :error,
            rule: :invalid_variable_identifier,
            format: format,
            identifier: variable.full_ref,
            sheet_id: variable.block.sheet_id,
            entity_type: "block",
            entity_id: variable.block.id,
            entity_label: variable.full_ref,
            message:
              dgettext(
                "projects",
                "Variable \"%{identifier}\" is not a valid runtime identifier in %{format}",
                identifier: variable.full_ref,
                format: format_label(format)
              )
          }
        ]
      end
    end)
  end

  defp valid_variable_identifier?(variable, format) when format in [:ink, :yarn] do
    variable.full_ref
    |> SerializerHelpers.shortcut_to_identifier()
    |> simple_identifier?()
  end

  defp valid_variable_identifier?(variable, :godot) do
    variable.sheet_shortcut
    |> SerializerHelpers.shortcut_to_identifier()
    |> simple_identifier?() and simple_identifier?(variable.variable_name)
  end

  defp valid_variable_identifier?(variable, format) when format in [:unreal, :articy] do
    dotted_identifier?(variable.sheet_shortcut) and dotted_identifier?(variable.variable_name)
  end

  defp valid_variable_identifier?(variable, :unity) do
    is_binary(variable.full_ref) and
      Regex.match?(~r/^[A-Za-z0-9_.-]+$/, variable.full_ref)
  end

  defp valid_variable_identifier?(_variable, _format), do: true

  defp dotted_identifier?(value) when is_binary(value) do
    segments = String.split(value, ".", trim: false)
    segments != [] and Enum.all?(segments, &simple_identifier?/1)
  end

  defp dotted_identifier?(_value), do: false

  defp simple_identifier?(value) when is_binary(value) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)
  end

  defp simple_identifier?(_value), do: false

  defp flow_identifier_collision_findings(:yarn, _flows), do: []

  defp flow_identifier_collision_findings(format, flows) do
    collision_findings(
      :flow_identifier_collision,
      format,
      flows,
      & &1.shortcut,
      fn identifier, colliding_flows, level ->
        first = hd(colliding_flows)

        %{
          level: level,
          rule: :flow_identifier_collision,
          format: format,
          identifier: identifier,
          flow_id: first.id,
          flow_name: first.name,
          entity_type: "flow",
          entity_id: first.id,
          entity_label: first.name,
          colliding_entity_ids: Enum.map(colliding_flows, & &1.id),
          message:
            dgettext(
              "projects",
              "Multiple flows collapse to the runtime identifier \"%{identifier}\" in %{format}",
              identifier: identifier,
              format: format_label(format)
            )
        }
      end
    )
  end

  defp sheet_identifier_collision_findings(format, sheets) do
    collision_findings(
      :sheet_identifier_collision,
      format,
      sheets,
      & &1.shortcut,
      fn identifier, colliding_sheets, level ->
        first = hd(colliding_sheets)

        %{
          level: level,
          rule: :sheet_identifier_collision,
          format: format,
          identifier: identifier,
          sheet_id: first.id,
          sheet_name: first.name,
          entity_type: "sheet",
          entity_id: first.id,
          entity_label: first.name,
          colliding_entity_ids: Enum.map(colliding_sheets, & &1.id),
          message:
            dgettext(
              "projects",
              "Multiple sheets collapse to the runtime identifier \"%{identifier}\" in %{format}",
              identifier: identifier,
              format: format_label(format)
            )
        }
      end
    )
  end

  defp hub_identifier_findings(format, flows) when format in @hub_identifier_formats do
    Enum.flat_map(flows, &hub_identifier_findings_for_flow(format, &1))
  end

  defp hub_identifier_findings(_format, _flows), do: []

  defp hub_identifier_findings_for_flow(format, flow) do
    hubs = Enum.filter(flow.nodes || [], &(&1.type == "hub"))

    invalid =
      Enum.flat_map(hubs, fn hub ->
        if valid_hub_identifier?(hub) do
          []
        else
          [
            node_finding(
              :error,
              :invalid_hub_identifier,
              flow,
              hub,
              dgettext(
                "projects",
                ~s(Hub "%{node}" in flow "%{flow}" has no valid target identifier for %{format}),
                node: FlowReadModel.node_label(hub),
                flow: flow.name,
                format: format_label(format)
              ),
              format: format
            )
          ]
        end
      end)

    invalid ++ hub_identifier_collision_findings(format, flow, hubs)
  end

  defp hub_identifier_collision_findings(:yarn, _flow, _hubs), do: []

  defp hub_identifier_collision_findings(format, flow, hubs) do
    hubs
    |> Enum.filter(&valid_hub_identifier?/1)
    |> Enum.group_by(&hub_identifier/1)
    |> Enum.flat_map(fn
      {_identifier, [_single]} ->
        []

      {identifier, colliding} ->
        [first | _rest] = colliding

        [
          node_finding(
            :error,
            :hub_identifier_collision,
            flow,
            first,
            dgettext(
              "projects",
              "Multiple hubs collapse to the target identifier \"%{identifier}\" in %{format}",
              identifier: identifier,
              format: format_label(format)
            ),
            format: format,
            identifier: identifier,
            colliding_entity_ids: Enum.map(colliding, & &1.id)
          )
        ]
    end)
  end

  defp valid_hub_identifier?(hub) do
    case hub_identifier_source(hub) do
      value when is_binary(value) and value != "" ->
        value
        |> SerializerHelpers.shortcut_to_identifier()
        |> then(&Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, &1))

      _value ->
        false
    end
  end

  defp hub_identifier(hub) do
    hub
    |> hub_identifier_source()
    |> SerializerHelpers.shortcut_to_identifier()
  end

  defp hub_identifier_source(hub) do
    data = hub.data || %{}

    case data["hub_id"] do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          StringUtils.present_label(data["label"], "hub_#{hub.id}")
        else
          value
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _value ->
        StringUtils.present_label(data["label"], "hub_#{hub.id}")
    end
  end

  defp yarn_node_identifier_collision_findings(:yarn, flows) do
    flow_entries =
      Enum.flat_map(flows, fn flow ->
        if valid_identifier?(flow.shortcut, :yarn) do
          [
            %{
              identifier: SerializerHelpers.shortcut_to_identifier(flow.shortcut),
              entity: "flow:#{flow.id}"
            }
          ]
        else
          []
        end
      end)

    hub_entries =
      Enum.flat_map(flows, fn flow ->
        flow.nodes
        |> Kernel.||([])
        |> Enum.filter(&(&1.type == "hub" and valid_hub_identifier?(&1)))
        |> Enum.map(fn hub ->
          %{identifier: hub_identifier(hub), entity: "hub:#{hub.id}"}
        end)
      end)

    (flow_entries ++ hub_entries)
    |> Enum.group_by(& &1.identifier)
    |> Enum.flat_map(fn
      {_identifier, [_single]} ->
        []

      {identifier, colliding} ->
        [
          %{
            level: :error,
            rule: :yarn_node_identifier_collision,
            format: :yarn,
            identifier: identifier,
            colliding_entity_ids: Enum.map(colliding, & &1.entity),
            message:
              dgettext(
                "projects",
                "Multiple flows or hubs collapse to the Yarn node title \"%{identifier}\"",
                identifier: identifier
              )
          }
        ]
    end)
  end

  defp yarn_node_identifier_collision_findings(_format, _flows), do: []

  defp variable_identifier_collision_findings(format, variables) do
    collision_findings(
      :variable_identifier_collision,
      format,
      variables,
      &variable_runtime_key(format, &1),
      fn runtime_key, colliding_variables, level ->
        first = hd(colliding_variables)
        identifier = variable_runtime_identifier(format, runtime_key)

        %{
          level: level,
          rule: :variable_identifier_collision,
          format: format,
          identifier: identifier,
          sheet_id: first.block.sheet_id,
          entity_type: "block",
          entity_id: first.block.id,
          entity_label: first.full_ref,
          colliding_entity_ids: Enum.map(colliding_variables, & &1.block.id),
          message:
            dgettext(
              "projects",
              "Multiple variables collapse to the runtime identifier \"%{identifier}\" in %{format}",
              identifier: identifier,
              format: format_label(format)
            )
        }
      end,
      &Function.identity/1
    )
  end

  defp variable_runtime_key(format, variable) when format in @flattened_variable_identifier_formats do
    SerializerHelpers.shortcut_to_identifier(variable.full_ref)
  end

  defp variable_runtime_key(:godot, variable) do
    {
      SerializerHelpers.shortcut_to_identifier(variable.sheet_shortcut),
      variable.variable_name
    }
  end

  defp variable_runtime_key(_format, variable), do: variable.full_ref

  defp variable_runtime_identifier(:godot, {folder, variable}), do: "#{folder}.#{variable}"
  defp variable_runtime_identifier(_format, identifier), do: identifier

  defp collision_findings(
         rule,
         format,
         entities,
         source_identifier,
         build_finding,
         normalize_identifier \\ &SerializerHelpers.shortcut_to_identifier/1
       ) do
    case integrity_level(rule, format) do
      level when level in [:error, :warning] ->
        entities
        |> Enum.filter(fn entity ->
          value = source_identifier.(entity)
          valid_collision_identifier?(value)
        end)
        |> Enum.group_by(fn entity ->
          entity
          |> source_identifier.()
          |> normalize_identifier.()
        end)
        |> Enum.flat_map(fn
          {_identifier, [_single]} -> []
          {identifier, colliding} -> [build_finding.(identifier, colliding, level)]
        end)

      :ignore ->
        []
    end
  end

  defp valid_collision_identifier?(value) when is_binary(value), do: value != ""
  defp valid_collision_identifier?(value) when is_tuple(value), do: true
  defp valid_collision_identifier?(_value), do: false

  defp dialogue_runtime_id_findings(format, flows) do
    dialogue_nodes =
      for flow <- flows,
          node <- flow.nodes || [],
          node.type == "dialogue",
          do: {flow, node}

    invalid =
      Enum.flat_map(dialogue_nodes, fn {flow, node} ->
        invalid_dialogue_id_findings(format, flow, node) ++
          invalid_response_id_findings(format, flow, node)
      end)

    invalid ++ duplicate_dialogue_id_findings(format, dialogue_nodes)
  end

  defp invalid_dialogue_id_findings(format, flow, node) do
    data = node.data || %{}
    localization_id = data["localization_id"]

    cond do
      invalid_runtime_id_shape?(localization_id) ->
        [
          node_finding(
            integrity_level(:invalid_dialogue_data, format),
            :invalid_dialogue_data,
            flow,
            node,
            dgettext(
              "projects",
              ~s(Dialogue "%{node}" in flow "%{flow}" has a localization ID that cannot be exported),
              node: FlowReadModel.node_label(node),
              flow: flow.name
            )
          )
        ]

      RuntimeKey.valid_dialogue_id?(localization_id) ->
        []

      true ->
        [
          node_finding(
            integrity_level(:invalid_dialogue_runtime_id, format),
            :invalid_dialogue_runtime_id,
            flow,
            node,
            dgettext(
              "projects",
              ~s(Dialogue "%{node}" in flow "%{flow}" needs a valid localization ID),
              node: FlowReadModel.node_label(node),
              flow: flow.name
            )
          )
        ]
    end
  end

  defp invalid_response_id_findings(format, flow, node) do
    responses = Map.get(node.data || %{}, "responses", [])

    if is_list(responses) do
      response_maps = Enum.filter(responses, &is_map/1)
      response_ids = Enum.map(response_maps, & &1["id"])

      invalid_shape_count =
        Enum.count(responses, &(not is_map(&1))) +
          Enum.count(response_ids, &invalid_runtime_id_shape?/1)

      exportable_response_ids =
        responses
        |> Enum.filter(&is_map/1)
        |> Enum.map(& &1["id"])
        |> Enum.reject(&invalid_runtime_id_shape?/1)

      invalid_count =
        Enum.count(exportable_response_ids, &(not RuntimeKey.valid_response_id?(&1)))

      duplicate_count =
        exportable_response_ids
        |> Enum.map(&response_runtime_key/1)
        |> Enum.frequencies()
        |> Enum.count(fn {_id, count} -> count > 1 end)

      []
      |> maybe_add_response_finding(
        format,
        flow,
        node,
        :invalid_response_data,
        invalid_shape_count
      )
      |> maybe_add_response_finding(format, flow, node, :invalid_response_runtime_id, invalid_count)
      |> maybe_add_response_finding(format, flow, node, :duplicate_response_runtime_id, duplicate_count)
    else
      [
        node_finding(
          integrity_level(:invalid_response_data, format),
          :invalid_response_data,
          flow,
          node,
          invalid_response_data_message(flow, node)
        )
      ]
    end
  end

  defp maybe_add_response_finding(findings, _format, _flow, _node, _rule, 0), do: findings

  defp maybe_add_response_finding(findings, format, flow, node, rule, count) do
    message =
      case rule do
        :invalid_response_data ->
          invalid_response_data_message(flow, node)

        :invalid_response_runtime_id ->
          dngettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" has one response without a valid ID),
            ~s(Dialogue "%{node}" in flow "%{flow}" has %{count} responses without valid IDs),
            count,
            node: FlowReadModel.node_label(node),
            flow: flow.name,
            count: count
          )

        :duplicate_response_runtime_id ->
          dngettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" repeats one response ID),
            ~s(Dialogue "%{node}" in flow "%{flow}" repeats %{count} response IDs),
            count,
            node: FlowReadModel.node_label(node),
            flow: flow.name,
            count: count
          )
      end

    [node_finding(integrity_level(rule, format), rule, flow, node, message, count: count) | findings]
  end

  defp invalid_response_data_message(flow, node) do
    dgettext(
      "projects",
      ~s(Dialogue "%{node}" in flow "%{flow}" has response data that cannot be exported),
      node: FlowReadModel.node_label(node),
      flow: flow.name
    )
  end

  defp response_runtime_key(value) when is_binary(value) or is_number(value) or is_atom(value), do: to_string(value)

  defp response_runtime_key(value), do: value

  defp invalid_runtime_id_shape?(value), do: is_map(value) or is_list(value)

  defp duplicate_dialogue_id_findings(format, dialogue_nodes) do
    dialogue_nodes
    |> Enum.group_by(fn {_flow, node} -> (node.data || %{})["localization_id"] end)
    |> Enum.flat_map(fn
      {_id, [_single]} ->
        []

      {id, duplicates} ->
        if RuntimeKey.valid_dialogue_id?(id) do
          [{flow, node} | _rest] = duplicates

          [
            node_finding(
              integrity_level(:duplicate_dialogue_runtime_id, format),
              :duplicate_dialogue_runtime_id,
              flow,
              node,
              dngettext(
                "projects",
                "Localization ID \"%{id}\" is used by one dialogue more than once",
                "Localization ID \"%{id}\" is used by %{count} dialogues",
                length(duplicates),
                id: id,
                count: length(duplicates)
              ),
              count: length(duplicates)
            )
          ]
        else
          []
        end
    end)
  end

  defp yarn_line_id_findings(:yarn, flows) do
    case Yarn.validate_line_ids(flows) do
      {:error, {:duplicate_localization_ids, identifiers}} ->
        [
          %{
            level: :error,
            rule: :yarn_line_id_collision,
            format: :yarn,
            identifiers: identifiers,
            message:
              dngettext(
                "projects",
                "One Yarn line ID collides after serialization",
                "%{count} Yarn line IDs collide after serialization",
                length(identifiers),
                count: length(identifiers)
              )
          }
        ]

      _valid_or_reported_by_runtime_rules ->
        []
    end
  end

  defp yarn_line_id_findings(_format, _flows), do: []

  defp control_reference_findings(_format, [], _active_flows), do: []

  defp control_reference_findings(format, flows, active_flows) do
    active_flows_by_id = Map.new(active_flows, &{to_string(&1.id), &1})
    active_flows_by_shortcut = Map.new(active_flows, &{&1.shortcut, &1})
    active_flow_ids = MapSet.new(active_flows, &to_string(&1.id))
    active_flow_shortcuts = MapSet.new(active_flows, & &1.shortcut)
    selected_flow_ids = MapSet.new(flows, &to_string(&1.id))
    selected_flow_shortcuts = MapSet.new(flows, & &1.shortcut)

    reference_findings =
      Enum.flat_map(flows, fn flow ->
        flow_control_reference_findings(
          format,
          flow,
          active_flow_ids,
          active_flow_shortcuts,
          selected_flow_ids,
          selected_flow_shortcuts
        ) ++
          external_target_identifier_findings(
            format,
            flow,
            active_flows_by_id,
            active_flows_by_shortcut,
            selected_flow_ids
          )
      end)

    reference_findings ++
      external_flow_identifier_collision_findings(
        format,
        flows,
        active_flows_by_id,
        active_flows_by_shortcut,
        selected_flow_ids
      )
  end

  defp flow_control_reference_findings(
         format,
         flow,
         active_flow_ids,
         active_flow_shortcuts,
         selected_flow_ids,
         selected_flow_shortcuts
       ) do
    nodes = flow.nodes || []
    connections = flow.connections || []
    node_ids = MapSet.new(nodes, & &1.id)
    hub_refs = FlowControlResolver.hub_reference_map(nodes)

    connected_targets_by_source =
      connections
      |> Enum.filter(&MapSet.member?(node_ids, &1.target_node_id))
      |> Enum.group_by(& &1.source_node_id, & &1.target_node_id)

    reference_context = %{
      hub_refs: hub_refs,
      connected_targets_by_source: connected_targets_by_source,
      active_flow_ids: active_flow_ids,
      active_flow_shortcuts: active_flow_shortcuts,
      selected_flow_ids: selected_flow_ids,
      selected_flow_shortcuts: selected_flow_shortcuts
    }

    Enum.flat_map(
      nodes,
      &control_reference_finding(
        format,
        flow,
        &1,
        reference_context
      )
    )
  end

  defp control_reference_finding(format, flow, node, context) do
    case control_reference_rule(
           node,
           context.hub_refs,
           context.connected_targets_by_source,
           context.active_flow_ids,
           context.active_flow_shortcuts,
           context.selected_flow_ids,
           context.selected_flow_shortcuts
         ) do
      nil ->
        []

      rule ->
        [
          node_finding(
            integrity_level(rule, format),
            rule,
            flow,
            node,
            control_reference_message(rule, flow, node, format),
            format: format
          )
        ]
    end
  end

  defp control_reference_rule(
         %{type: "jump"} = node,
         hub_refs,
         _connected_targets_by_source,
         active_flow_ids,
         active_flow_shortcuts,
         selected_flow_ids,
         selected_flow_shortcuts
       ) do
    data = node.data || %{}
    hub_ref = data["target_hub_id"] || data["hub_id"]
    flow_reference_id = FlowControlResolver.referenced_flow_id(data)
    flow_shortcut = FlowControlResolver.referenced_flow_shortcut(data)

    cond do
      invalid_runtime_id_shape?(hub_ref) or invalid_runtime_id_shape?(flow_shortcut) ->
        :invalid_control_reference_data

      present?(hub_ref) ->
        reference_rule(
          not is_nil(FlowControlResolver.hub_target(hub_refs, hub_ref)),
          :stale_jump_target
        )

      present?(flow_reference_id) or present?(flow_shortcut) ->
        flow_reference_rule(
          data,
          :missing_jump_target,
          :stale_jump_target,
          active_flow_ids,
          active_flow_shortcuts,
          selected_flow_ids,
          selected_flow_shortcuts
        )

      true ->
        :missing_jump_target
    end
  end

  defp control_reference_rule(
         %{type: "subflow"} = node,
         _hub_refs,
         _connected_targets_by_source,
         active_flow_ids,
         active_flow_shortcuts,
         selected_flow_ids,
         selected_flow_shortcuts
       ) do
    flow_reference_rule(
      node.data || %{},
      :missing_subflow_reference,
      :stale_subflow_reference,
      active_flow_ids,
      active_flow_shortcuts,
      selected_flow_ids,
      selected_flow_shortcuts
    )
  end

  defp control_reference_rule(
         %{type: "exit"} = node,
         _hub_refs,
         _connected_targets_by_source,
         active_flow_ids,
         active_flow_shortcuts,
         selected_flow_ids,
         selected_flow_shortcuts
       ) do
    data = node.data || %{}

    if data["exit_mode"] == "flow_reference" do
      flow_reference_rule(
        data,
        :missing_exit_flow_reference,
        :stale_exit_flow_reference,
        active_flow_ids,
        active_flow_shortcuts,
        selected_flow_ids,
        selected_flow_shortcuts
      )
    end
  end

  defp control_reference_rule(
         _node,
         _hub_refs,
         _connected_targets_by_source,
         _active_flow_ids,
         _active_flow_shortcuts,
         _selected_flow_ids,
         _selected_flow_shortcuts
       ), do: nil

  defp external_target_identifier_findings(format, flow, active_flows_by_id, active_flows_by_shortcut, selected_flow_ids) do
    Enum.flat_map(flow.nodes || [], fn node ->
      with %{} = data <- flow_reference_data(node),
           %{} = target <-
             referenced_active_flow(data, active_flows_by_id, active_flows_by_shortcut),
           false <- MapSet.member?(selected_flow_ids, to_string(target.id)),
           false <- valid_identifier?(target.shortcut, format),
           level when level in [:error, :warning] <-
             integrity_level(:invalid_flow_identifier, format) do
        [
          node_finding(
            level,
            :invalid_flow_identifier,
            flow,
            node,
            dgettext(
              "projects",
              ~s("%{node}" in flow "%{flow}" targets flow "%{target}", which needs a valid shortcut for the %{format} export),
              node: FlowReadModel.node_label(node),
              flow: flow.name,
              target: target.name,
              format: format_label(format)
            ),
            format: format,
            target_flow_id: target.id,
            target_flow_name: target.name
          )
        ]
      else
        _valid_or_unavailable_target -> []
      end
    end)
  end

  defp flow_reference_data(%{type: "subflow"} = node), do: node.data || %{}

  defp flow_reference_data(%{type: "exit"} = node) do
    data = node.data || %{}
    if data["exit_mode"] == "flow_reference", do: data
  end

  defp flow_reference_data(%{type: "jump"} = node) do
    data = node.data || %{}
    if is_nil(FlowControlResolver.target_hub_id(data)), do: data
  end

  defp flow_reference_data(_node), do: nil

  defp referenced_active_flow(data, active_flows_by_id, active_flows_by_shortcut) do
    referenced_id = FlowControlResolver.referenced_flow_id(data)
    referenced_shortcut = FlowControlResolver.referenced_flow_shortcut(data)

    by_id = if present?(referenced_id), do: active_flows_by_id[referenced_id]
    by_shortcut = if present?(referenced_shortcut), do: active_flows_by_shortcut[referenced_shortcut]

    by_id || by_shortcut
  end

  defp external_flow_identifier_collision_findings(
         format,
         flows,
         active_flows_by_id,
         active_flows_by_shortcut,
         selected_flow_ids
       )
       when format in @normalized_identifier_formats do
    external_flows =
      flows
      |> Enum.flat_map(
        &external_referenced_flows(
          &1,
          active_flows_by_id,
          active_flows_by_shortcut,
          selected_flow_ids
        )
      )
      |> Enum.uniq_by(& &1.id)

    external_ids = MapSet.new(external_flows, & &1.id)

    (flows ++ external_flows)
    |> Enum.filter(&valid_identifier?(&1.shortcut, format))
    |> Enum.uniq_by(& &1.id)
    |> Enum.group_by(&SerializerHelpers.shortcut_to_identifier(&1.shortcut))
    |> Enum.flat_map(fn
      {_identifier, [_single]} ->
        []

      {identifier, colliding} ->
        if Enum.any?(colliding, &MapSet.member?(external_ids, &1.id)) do
          [first | _rest] = colliding

          [
            %{
              level: :error,
              rule: :flow_identifier_collision,
              format: format,
              identifier: identifier,
              flow_id: first.id,
              flow_name: first.name,
              entity_type: "flow",
              entity_id: first.id,
              entity_label: first.name,
              colliding_entity_ids: Enum.map(colliding, & &1.id),
              message:
                dgettext(
                  "projects",
                  "A selected flow and an external target collapse to the runtime identifier \"%{identifier}\" in %{format}",
                  identifier: identifier,
                  format: format_label(format)
                )
            }
          ]
        else
          []
        end
    end)
  end

  defp external_flow_identifier_collision_findings(
         _format,
         _flows,
         _active_flows_by_id,
         _active_flows_by_shortcut,
         _selected_flow_ids
       ), do: []

  defp external_referenced_flows(flow, active_flows_by_id, active_flows_by_shortcut, selected_flow_ids) do
    Enum.flat_map(flow.nodes || [], fn node ->
      with %{} = data <- flow_reference_data(node),
           %{} = target <-
             referenced_active_flow(data, active_flows_by_id, active_flows_by_shortcut),
           false <- MapSet.member?(selected_flow_ids, to_string(target.id)) do
        [target]
      else
        _selected_or_unavailable_target -> []
      end
    end)
  end

  defp flow_reference_rule(
         data,
         missing_rule,
         stale_rule,
         active_flow_ids,
         active_flow_shortcuts,
         selected_flow_ids,
         selected_flow_shortcuts
       ) do
    reference_id = data["referenced_flow_id"] || data["target_flow_id"] || data["flow_id"]
    reference_shortcut = FlowControlResolver.referenced_flow_shortcut(data)

    cond do
      invalid_runtime_id_shape?(reference_id) or invalid_runtime_id_shape?(reference_shortcut) ->
        :invalid_control_reference_data

      present?(reference_id) ->
        scoped_reference_rule(
          to_string(reference_id),
          active_flow_ids,
          selected_flow_ids,
          stale_rule
        )

      present?(reference_shortcut) ->
        scoped_reference_rule(
          reference_shortcut,
          active_flow_shortcuts,
          selected_flow_shortcuts,
          stale_rule
        )

      true ->
        missing_rule
    end
  end

  defp reference_rule(true, _stale_rule), do: nil
  defp reference_rule(false, stale_rule), do: stale_rule

  defp scoped_reference_rule(reference, active_references, selected_references, stale_rule) do
    cond do
      not MapSet.member?(active_references, reference) -> stale_rule
      MapSet.member?(selected_references, reference) -> nil
      true -> :external_flow_reference
    end
  end

  defp control_reference_message(rule, flow, node, format) do
    cond do
      rule in [:missing_jump_target, :missing_subflow_reference, :missing_exit_flow_reference] ->
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" has no configured target; %{format} cannot preserve the transition),
          node: FlowReadModel.node_label(node),
          flow: flow.name,
          format: format_label(format)
        )

      rule == :external_flow_reference ->
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" targets a flow outside this partial export),
          node: FlowReadModel.node_label(node),
          flow: flow.name
        )

      rule == :invalid_control_reference_data ->
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" has target data that cannot be exported),
          node: FlowReadModel.node_label(node),
          flow: flow.name
        )

      true ->
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" targets content that no longer exists; %{format} cannot preserve the transition),
          node: FlowReadModel.node_label(node),
          flow: flow.name,
          format: format_label(format)
        )
    end
  end

  defp variable_reference_findings(_format, [], _referenceable_variables, _stale_node_variable_refs_by_flow), do: []

  defp variable_reference_findings(format, flows, referenceable_variables, stale_node_variable_refs_by_flow) do
    referenceable_refs =
      referenceable_variables
      |> Enum.map(&variable_descriptor_ref/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.flat_map(flows, fn flow ->
      Enum.flat_map(
        flow.nodes || [],
        &variable_reference_findings(
          &1,
          flow,
          format,
          referenceable_refs,
          Map.get(stale_node_variable_refs_by_flow, flow.id, %{})
        )
      )
    end)
  end

  defp variable_reference_findings(node, flow, format, referenceable_refs, tracked_stale_refs_by_node) do
    references =
      node
      |> node_variable_references()
      |> Enum.uniq()
      |> Enum.sort()

    exported_refs = MapSet.new(references)
    missing_refs = MapSet.difference(exported_refs, referenceable_refs)

    tracked_stale_refs =
      tracked_stale_refs_by_node
      |> Map.get(node.id, MapSet.new())
      |> MapSet.intersection(exported_refs)

    stale_refs =
      missing_refs
      |> MapSet.union(tracked_stale_refs)
      |> Enum.sort()

    tracked_stale? = MapSet.size(tracked_stale_refs) > 0

    stale_variable_reference_finding(
      node,
      flow,
      format,
      stale_refs,
      tracked_stale?
    )
  end

  defp stale_variable_reference_finding(_node, _flow, _format, [], false), do: []

  defp stale_variable_reference_finding(node, flow, format, stale_refs, tracked_stale?) do
    [
      node_finding(
        integrity_level(:stale_variable_reference, format),
        :stale_variable_reference,
        flow,
        node,
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" references a variable that no longer exists),
          node: FlowReadModel.node_label(node),
          flow: flow.name
        ),
        format: format,
        details: %{
          references: stale_refs,
          tracked_reference_stale: tracked_stale?
        }
      )
    ]
  end

  defp node_variable_references(node) do
    data = node.data || %{}

    condition_refs =
      case node.type do
        "condition" -> condition_variable_references(data["condition"])
        "dialogue" -> condition_variable_references(data["condition"]) ++ response_condition_references(data)
        _type -> []
      end

    assignment_refs =
      case node.type do
        "instruction" -> assignment_variable_references(data["assignments"])
        "dialogue" -> response_assignment_references(data)
        _type -> []
      end

    condition_refs ++ assignment_refs
  end

  defp response_condition_references(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.flat_map(fn
      response when is_map(response) -> condition_variable_references(response["condition"])
      _response -> []
    end)
  end

  defp response_assignment_references(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.flat_map(fn
      response when is_map(response) ->
        response
        |> response_assignments()
        |> assignment_variable_references()

      _response ->
        []
    end)
  end

  defp condition_variable_references(raw_condition) do
    raw_condition
    |> decode_condition()
    |> FlowCondition.extract_all_rules()
    |> Enum.filter(&condition_export_candidate?/1)
    |> Enum.flat_map(fn rule ->
      variable_reference(rule["sheet"], rule["variable"])
    end)
  end

  defp assignment_variable_references(assignments) when is_list(assignments) do
    Enum.flat_map(assignments, &assignment_references/1)
  end

  defp assignment_variable_references(_assignments), do: []

  defp assignment_references(assignment) when is_map(assignment) do
    if instruction_export_candidate?(assignment) do
      variable_reference(assignment["sheet"], assignment["variable"]) ++
        assignment_read_references(assignment)
    else
      []
    end
  end

  defp assignment_references(_assignment), do: []

  defp assignment_read_references(%{"value_type" => "variable_ref"} = assignment) do
    variable_reference(assignment["value_sheet"], assignment["value"])
  end

  defp assignment_read_references(_assignment), do: []

  defp variable_reference(sheet, variable)
       when is_binary(sheet) and sheet != "" and is_binary(variable) and variable != "", do: ["#{sheet}.#{variable}"]

  defp variable_reference(_sheet, _variable), do: []

  defp variable_type_mismatch_findings(:yarn, flows, referenceable_variables) do
    type_map = unambiguous_variable_type_map(referenceable_variables)

    Enum.flat_map(flows, fn flow ->
      Enum.flat_map(flow.nodes || [], &variable_type_mismatch_finding(&1, flow, type_map))
    end)
  end

  defp variable_type_mismatch_findings(_format, _flows, _referenceable_variables), do: []

  defp variable_type_mismatch_finding(node, flow, type_map) do
    if node_has_variable_type_mismatch?(node, type_map) do
      [
        node_finding(
          :warning,
          :variable_type_mismatch,
          flow,
          node,
          dgettext(
            "projects",
            ~s("%{node}" in flow "%{flow}" contains an expression that cannot be exported to %{format}),
            node: FlowReadModel.node_label(node),
            flow: flow.name,
            format: format_label(:yarn)
          ),
          format: :yarn
        )
      ]
    else
      []
    end
  end

  defp unambiguous_variable_type_map(referenceable_variables) do
    referenceable_variables
    |> Enum.group_by(&variable_descriptor_ref/1)
    |> Enum.reduce(%{}, fn
      {nil, _variables}, type_map ->
        type_map

      {reference, variables}, type_map ->
        types =
          variables
          |> Enum.map(&Map.get(&1, :block_type))
          |> Enum.filter(&is_binary/1)
          |> Enum.uniq()

        case types do
          [type] -> Map.put(type_map, reference, type)
          _ambiguous_or_missing -> type_map
        end
    end)
  end

  defp node_has_variable_type_mismatch?(node, type_map) do
    data = node.data || %{}

    case node.type do
      "instruction" ->
        FlowInstruction.has_type_warnings?(data["assignments"] || [], type_map)

      "dialogue" ->
        data
        |> Map.get("responses", [])
        |> list_or_empty()
        |> Enum.any?(fn
          response when is_map(response) ->
            FlowInstruction.has_type_warnings?(response_assignments(response), type_map)

          _response ->
            false
        end)

      _type ->
        false
    end
  end

  defp expression_findings(format, flows) do
    Enum.flat_map(flows, fn flow ->
      Enum.flat_map(flow.nodes || [], &node_expression_findings(format, flow, &1))
    end)
  end

  defp node_expression_findings(format, flow, node) do
    data = node.data || %{}

    condition_sources =
      case node.type do
        "condition" -> [{:condition, data["condition"]}]
        "dialogue" -> [{:condition, data["condition"]}] ++ response_conditions(data)
        _type -> []
      end

    instruction_sources =
      case node.type do
        "instruction" -> [{:instruction, data["assignments"]}]
        "dialogue" -> response_instructions(data)
        _type -> []
      end

    Enum.flat_map(condition_sources, fn {source, condition} ->
      transpile_condition_findings(format, flow, node, source, condition)
    end) ++
      Enum.flat_map(instruction_sources, fn {source, assignments} ->
        transpile_instruction_findings(format, flow, node, source, assignments)
      end) ++ serializer_semantic_loss_findings(format, flow, node)
  end

  defp serializer_semantic_loss_findings(format, flow, node) do
    case node.type do
      "condition" -> condition_semantic_loss_findings(format, flow, node)
      "dialogue" -> dialogue_semantic_loss_findings(format, flow, node)
      "subflow" -> subflow_semantic_loss_findings(format, flow, node)
      "exit" -> exit_semantic_loss_findings(format, flow, node)
      _type -> []
    end
  end

  defp condition_semantic_loss_findings(format, flow, node) do
    data = node.data || %{}

    unsupported_switch_group_findings(format, flow, node, data) ++
      merged_switch_branch_findings(format, flow, node, data) ++
      condition_branch_routing_findings(format, flow, node)
  end

  defp unsupported_switch_group_findings(format, flow, node, data) do
    if data["switch_mode"] == true and switch_has_group?(data["condition"]) do
      [
        semantic_loss_finding(
          :error,
          flow,
          node,
          format,
          dgettext("projects", "Grouped switch cases cannot be represented by this serializer")
        )
      ]
    else
      []
    end
  end

  defp merged_switch_branch_findings(format, flow, node, data) do
    switch_cases = FlowControlResolver.switch_case_defs(data["condition"])
    explicit_cases = list_or_empty(data["cases"])

    if (format in [:ink, :yarn] and
          data["switch_mode"] == true and length(switch_cases) > 1) or
         (format in [:ink, :yarn, :godot] and length(explicit_cases) > 2) do
      [
        semantic_loss_finding(
          :error,
          flow,
          node,
          format,
          dgettext("projects", "Switch branches are merged by this serializer")
        )
      ]
    else
      []
    end
  end

  defp condition_branch_routing_findings(format, flow, node) do
    if format in [:unreal, :articy] and multiple_output_pins?(flow, node) do
      [
        semantic_loss_finding(
          :warning,
          flow,
          node,
          format,
          dgettext("projects", "Condition branch routing is not represented by this serializer")
        )
      ]
    else
      []
    end
  end

  defp dialogue_semantic_loss_findings(format, flow, node) do
    data = node.data || %{}

    response_assignment_semantic_loss_findings(format, flow, node, data) ++
      dialogue_condition_semantic_loss_findings(format, flow, node, data) ++
      response_routing_semantic_loss_findings(format, flow, node, data)
  end

  defp response_assignment_semantic_loss_findings(format, flow, node, data) do
    if format == :articy and has_response_assignments?(data) do
      [
        semantic_loss_finding(
          :warning,
          flow,
          node,
          format,
          dgettext("projects", "Response assignments are not represented in articy:draft XML")
        )
      ]
    else
      []
    end
  end

  defp has_response_assignments?(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.any?(fn
      response when is_map(response) ->
        response
        |> response_assignments()
        |> then(&(is_list(&1) and &1 != []))

      _response ->
        false
    end)
  end

  defp dialogue_condition_semantic_loss_findings(format, flow, node, data) do
    if not noop_condition?(data["condition"]) and data["condition"] not in [nil, ""] do
      dialogue_condition_semantic_loss_findings(format, flow, node)
    else
      []
    end
  end

  defp dialogue_condition_semantic_loss_findings(format, flow, node) when format in @linear_formats do
    [
      semantic_loss_finding(
        :error,
        flow,
        node,
        format,
        dgettext("projects", "Dialogue conditions are not represented by this serializer")
      )
    ]
  end

  defp dialogue_condition_semantic_loss_findings(:articy, flow, node) do
    [
      semantic_loss_finding(
        :warning,
        flow,
        node,
        :articy,
        dgettext("projects", "Dialogue conditions are not represented in articy:draft XML")
      )
    ]
  end

  defp dialogue_condition_semantic_loss_findings(_format, _flow, _node), do: []

  defp response_routing_semantic_loss_findings(format, flow, node, data) do
    if format in [:unreal, :articy] and response_routes_differ?(flow, node, data) do
      [
        semantic_loss_finding(
          :warning,
          flow,
          node,
          format,
          dgettext("projects", "Response-specific routing is not represented by this serializer")
        )
      ]
    else
      []
    end
  end

  defp subflow_semantic_loss_findings(:unreal, flow, node) do
    [
      semantic_loss_finding(
        :error,
        flow,
        node,
        :unreal,
        dgettext("projects", "Subflow transitions are not represented in Unreal CSV")
      )
    ]
  end

  defp subflow_semantic_loss_findings(:articy, flow, node) do
    if multiple_output_pins?(flow, node) do
      [
        semantic_loss_finding(
          :warning,
          flow,
          node,
          :articy,
          dgettext("projects", "Subflow return routing is not represented by this serializer")
        )
      ]
    else
      []
    end
  end

  defp subflow_semantic_loss_findings(format, flow, node) when format in @linear_formats do
    connected_pins =
      flow.connections
      |> Kernel.||([])
      |> Enum.filter(&(&1.source_node_id == node.id))
      |> Enum.map(& &1.source_pin)
      |> Enum.uniq()

    if length(connected_pins) > 1 do
      [
        semantic_loss_finding(
          :error,
          flow,
          node,
          format,
          dgettext(
            "projects",
            "Multiple subflow return branches cannot be represented by this serializer"
          )
        )
      ]
    else
      []
    end
  end

  defp subflow_semantic_loss_findings(_format, _flow, _node), do: []

  defp exit_semantic_loss_findings(format, flow, node) when format in [:unreal, :articy] do
    data = node.data || %{}

    if data["exit_mode"] == "flow_reference" do
      [
        semantic_loss_finding(
          :warning,
          flow,
          node,
          format,
          dgettext("projects", "Exit flow references are not represented by this serializer")
        )
      ]
    else
      []
    end
  end

  defp exit_semantic_loss_findings(_format, _flow, _node), do: []

  defp response_routes_differ?(flow, node, data) do
    response_ids =
      data
      |> Map.get("responses", [])
      |> list_or_empty()
      |> Enum.flat_map(fn
        %{"id" => id} when is_binary(id) and id != "" -> [id]
        _response -> []
      end)

    response_ids
    |> Enum.map(fn response_id ->
      flow.connections
      |> Kernel.||([])
      |> Enum.filter(fn connection ->
        connection.source_node_id == node.id and
          connection.source_pin in [response_id, "response_#{response_id}"]
      end)
      |> MapSet.new(& &1.target_node_id)
    end)
    |> Enum.uniq()
    |> length()
    |> Kernel.>(1)
  end

  defp multiple_output_pins?(flow, node) do
    flow.connections
    |> Kernel.||([])
    |> Enum.filter(&(&1.source_node_id == node.id))
    |> Enum.map(& &1.source_pin)
    |> Enum.uniq()
    |> length()
    |> Kernel.>(1)
  end

  defp semantic_loss_finding(level, flow, node, format, detail) do
    node_finding(
      level,
      :semantic_loss,
      flow,
      node,
      dgettext(
        "projects",
        ~s("%{node}" in flow "%{flow}" loses behavior in %{format}: %{detail}),
        node: FlowReadModel.node_label(node),
        flow: flow.name,
        format: format_label(format),
        detail: detail
      ),
      format: format,
      details: %{reason: detail}
    )
  end

  defp switch_has_group?(%{"blocks" => blocks}) when is_list(blocks) do
    Enum.any?(blocks, &match?(%{"type" => "group"}, &1))
  end

  defp switch_has_group?(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> switch_has_group?(decoded)
      _invalid -> false
    end
  end

  defp switch_has_group?(_condition), do: false

  defp response_conditions(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.with_index(1)
    |> Enum.map(fn
      {response, index} when is_map(response) -> {{:response_condition, index}, response["condition"]}
      {_response, index} -> {{:response_condition, index}, :invalid}
    end)
  end

  defp response_instructions(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.with_index(1)
    |> Enum.map(fn
      {response, index} when is_map(response) ->
        {{:response_instruction, index}, response_assignments(response)}

      {_response, index} ->
        {{:response_instruction, index}, :invalid}
    end)
  end

  defp transpile_condition_findings(_format, _flow, _node, _source, condition) when condition in [nil, ""], do: []

  defp transpile_condition_findings(format, flow, node, source, condition) do
    cond do
      condition_structure_invalid?(condition) ->
        [
          expression_error_finding(
            flow,
            node,
            source,
            format,
            :invalid_condition_structure
          )
        ]

      noop_condition?(condition) ->
        []

      true ->
        rules =
          condition
          |> decode_condition()
          |> FlowCondition.extract_all_rules()

        export_candidates = Enum.filter(rules, &condition_export_candidate?/1)

        cond do
          Enum.any?(rules, &corrupt_condition_rule?/1) ->
            [
              expression_error_finding(
                flow,
                node,
                source,
                format,
                :invalid_condition_rule
              )
            ]

          export_candidates == [] ->
            []

          Enum.any?(export_candidates, &(not complete_condition_rule?(&1))) ->
            [
              expression_error_finding(
                flow,
                node,
                source,
                format,
                :incomplete_condition_rule
              )
            ]

          true ->
            transpile_complete_condition_findings(
              condition,
              format,
              flow,
              node,
              source
            )
        end
    end
  end

  defp transpile_complete_condition_findings(condition, format, flow, node, source) do
    case ExpressionTranspiler.transpile_condition(condition, format) do
      {:ok, expression, warnings} ->
        empty_expression_finding(expression, flow, node, source, format) ++
          transpiler_warning_findings(warnings, flow, node, source, format)

      {:error, reason} ->
        [expression_error_finding(flow, node, source, format, reason)]
    end
  end

  defp transpile_instruction_findings(_format, _flow, _node, _source, assignments) when assignments in [nil, []], do: []

  defp transpile_instruction_findings(format, flow, node, source, assignments) when is_list(assignments) do
    export_candidates = Enum.filter(assignments, &instruction_export_candidate?/1)

    cond do
      export_candidates == [] ->
        []

      Enum.any?(export_candidates, &(not FlowInstruction.complete_assignment?(&1))) ->
        [
          expression_error_finding(
            flow,
            node,
            source,
            format,
            :incomplete_instruction_assignment
          )
        ]

      true ->
        case ExpressionTranspiler.transpile_instruction(assignments, format) do
          {:ok, _expression, warnings} ->
            transpiler_warning_findings(warnings, flow, node, source, format)

          {:error, reason} ->
            [expression_error_finding(flow, node, source, format, reason)]
        end
    end
  end

  defp transpile_instruction_findings(format, flow, node, source, _assignments) do
    [
      expression_error_finding(
        flow,
        node,
        source,
        format,
        :invalid_instruction_structure
      )
    ]
  end

  defp empty_expression_finding(expression, _flow, _node, _source, _format)
       when is_binary(expression) and expression != "", do: []

  defp empty_expression_finding(_expression, flow, node, source, format) do
    [
      expression_error_finding(
        flow,
        node,
        source,
        format,
        :empty_generated_expression
      )
    ]
  end

  defp expression_error_finding(flow, node, source, format, reason) do
    node_finding(
      integrity_level(:invalid_export_expression, format),
      :invalid_export_expression,
      flow,
      node,
      dgettext(
        "projects",
        ~s("%{node}" in flow "%{flow}" contains an expression that cannot be exported to %{format}),
        node: FlowReadModel.node_label(node),
        flow: flow.name,
        format: format_label(format)
      ),
      expression_source: source,
      reason: reason,
      format: format
    )
  end

  defp transpiler_warning_findings(warnings, flow, node, source, format) do
    Enum.map(warnings, fn warning ->
      node_finding(
        :warning,
        warning.type,
        flow,
        node,
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}": %{warning}),
          node: FlowReadModel.node_label(node),
          flow: flow.name,
          warning: warning.message
        ),
        expression_source: source,
        format: format,
        details: Map.get(warning, :details, %{})
      )
    end)
  end

  defp node_finding(level, rule, flow, node, message, extra \\ []) do
    Map.merge(
      %{
        level: level,
        rule: rule,
        message: message,
        flow_id: flow.id,
        flow_name: flow.name,
        node_id: node.id,
        node_type: node.type,
        entity_type: node.type,
        entity_id: node.id,
        entity_label: FlowReadModel.node_label(node)
      },
      Map.new(extra)
    )
  end

  defp declared_variables(_project_id, []), do: []

  defp declared_variables(project_id, sheets) do
    if Enum.all?(sheets, &is_list(Map.get(&1, :blocks))) do
      SerializerHelpers.collect_variables(sheets)
    else
      selected_sheet_ids = Enum.map(sheets, & &1.id)

      project_id
      |> Sheets.list_sheets_for_export(filter_ids: selected_sheet_ids)
      |> SerializerHelpers.collect_variables()
    end
  end

  defp referenceable_variables(_project_id, []), do: []
  defp referenceable_variables(project_id, _flows), do: FlowReadModel.list_referenceable_variables(project_id)

  defp active_flows(_project_id, [], _validation_context), do: []

  defp active_flows(project_id, _artifact_flows, validation_context) do
    Map.get_lazy(validation_context, :active_flows, fn -> FlowReadModel.list_flows(project_id) end)
  end

  defp stale_node_variable_refs_by_flow(flows) do
    flow_ids =
      flows
      |> Enum.map(& &1.id)
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.uniq()

    References.list_stale_node_variable_refs_by_flow(flow_ids)
  end

  defp variable_descriptor_ref(%{full_ref: full_ref}) when is_binary(full_ref) and full_ref != "", do: full_ref

  defp variable_descriptor_ref(%{sheet_shortcut: sheet, variable_name: variable})
       when is_binary(sheet) and sheet != "" and is_binary(variable) and variable != "", do: "#{sheet}.#{variable}"

  defp variable_descriptor_ref(_variable), do: nil

  defp response_assignments(response) do
    case response["instruction_assignments"] do
      [_assignment | _rest] = assignments -> assignments
      [] -> parse_instruction(response["instruction"])
      nil -> parse_instruction(response["instruction"])
      invalid -> invalid
    end
  end

  defp decode_condition(condition) do
    {:ok, decoded} = ExpressionHelpers.decode_condition(condition)
    decoded
  end

  defp noop_condition?(%{"logic" => logic, "rules" => []}) when logic in ["all", "any"], do: true

  defp noop_condition?(%{"logic" => logic, "blocks" => blocks} = condition)
       when logic in ["all", "any"] and is_list(blocks) do
    FlowCondition.extract_all_rules(condition) == []
  end

  defp noop_condition?(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> noop_condition?(decoded)
      _result -> false
    end
  end

  defp noop_condition?(_condition), do: false

  defp condition_structure_invalid?(condition) do
    case decode_condition(condition) do
      %{} = decoded -> match?({:error, _reason}, FlowCondition.validate(decoded))
      nil -> not noop_condition?(condition)
    end
  end

  defp complete_condition_rule?(rule) when is_map(rule) do
    operator = rule["operator"]

    complete_reference?(rule["sheet"], rule["variable"]) and
      FlowCondition.valid_operator?(operator) and
      (not FlowCondition.operator_requires_value?(operator) or
         exportable_condition_value?(rule["value"]))
  end

  defp complete_condition_rule?(_rule), do: false

  defp condition_export_candidate?(%{"sheet" => sheet, "variable" => variable, "operator" => operator}) do
    complete_reference?(sheet, variable) and is_binary(operator) and operator != ""
  end

  defp condition_export_candidate?(_rule), do: false

  defp corrupt_condition_rule?(rule) when is_map(rule) do
    operator = rule["operator"]

    impossible_condition_field?(rule["sheet"]) or
      impossible_condition_field?(rule["variable"]) or
      impossible_condition_operator?(operator) or
      impossible_condition_value?(operator, rule["value"])
  end

  defp corrupt_condition_rule?(_rule), do: true

  defp impossible_condition_field?(value), do: not (is_nil(value) or is_binary(value))

  defp impossible_condition_operator?(operator) when operator in [nil, ""], do: false
  defp impossible_condition_operator?(operator) when is_binary(operator), do: not FlowCondition.valid_operator?(operator)
  defp impossible_condition_operator?(_operator), do: true

  defp impossible_condition_value?(_operator, value) when value in [nil, ""], do: false

  defp impossible_condition_value?(operator, value) do
    FlowCondition.valid_operator?(operator) and
      FlowCondition.operator_requires_value?(operator) and
      not exportable_condition_value?(value)
  end

  defp instruction_export_candidate?(%{"sheet" => sheet, "variable" => variable, "operator" => operator}) do
    complete_reference?(sheet, variable) and is_binary(operator) and operator != ""
  end

  defp instruction_export_candidate?(_assignment), do: false

  defp complete_reference?(sheet, variable) do
    is_binary(sheet) and sheet != "" and is_binary(variable) and variable != ""
  end

  defp exportable_condition_value?(value) when is_binary(value), do: value != ""
  defp exportable_condition_value?(value), do: is_number(value) or is_boolean(value)

  defp integrity_level(rule, :unity) when rule in @runtime_id_rules, do: :warning
  defp integrity_level(rule, _format) when rule in @runtime_id_rules, do: :error
  defp integrity_level(rule, _format) when rule in @blocking_runtime_id_rules, do: :error

  defp integrity_level(rule, :unity) when rule in @required_identifier_rules, do: :warning
  defp integrity_level(rule, _format) when rule in @required_identifier_rules, do: :error

  defp integrity_level(rule, format) when rule in @normalized_entity_collision_rules do
    if format in @normalized_identifier_formats, do: :error, else: :ignore
  end

  defp integrity_level(:variable_identifier_collision, _format), do: :error

  defp integrity_level(:external_flow_reference, _format), do: :warning
  defp integrity_level(:invalid_control_reference_data, _format), do: :error

  defp integrity_level(:stale_variable_reference, format) do
    if format in @stale_variable_blocking_formats, do: :error, else: :warning
  end

  defp integrity_level(rule, format) when rule in @control_reference_rules do
    if format in @control_reference_blocking_formats, do: :error, else: :warning
  end

  defp integrity_level(:invalid_export_expression, _format), do: :error

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp parse_instruction(nil), do: []
  defp parse_instruction(""), do: []

  defp parse_instruction(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _result -> :invalid
    end
  end

  defp parse_instruction(value), do: value

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp format_label(format) do
    format
    |> to_string()
    |> String.capitalize()
  end
end
