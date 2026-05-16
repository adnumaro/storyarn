defmodule Storyarn.Exports.Serializers.UnityJSON do
  @moduledoc """
  Unity Dialogue System JSON serializer.

  Produces JSON shaped for Pixel Crushers Dialogue System for Unity's
  DialogueDatabase JSON importer. Storyarn-only metadata is preserved as custom
  Dialogue System fields.
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.ExpressionTranspiler
  alias Storyarn.Exports.Serializers.FlowControlResolver
  alias Storyarn.Exports.Serializers.Helpers

  @text_type 0
  @boolean_type 2
  @files_type 3
  @localization_type 4
  @actor_type 5

  @text_type_string "CustomFieldType_Text"
  @boolean_type_string "CustomFieldType_Boolean"
  @files_type_string "CustomFieldType_Files"
  @localization_type_string "CustomFieldType_Localization"
  @actor_type_string "CustomFieldType_Actor"

  @player_actor_id 1
  @entry_width 160.0
  @entry_height 30.0
  @normal_priority 2

  @impl true
  def content_type, do: "application/json"

  @impl true
  def file_extension, do: "json"

  @impl true
  def format_label, do: "Unity Dialogue System (JSON)"

  @impl true
  def supported_sections, do: [:flows, :sheets, :localization]

  @impl true
  def serialize(project_data, %ExportOptions{} = opts) do
    sheets = Map.get(project_data, :sheets, []) || []
    flows = Map.get(project_data, :flows, []) || []
    project = Map.get(project_data, :project)
    variables = Helpers.collect_variables(sheets)
    actor_id_map = build_actor_id_map(sheets)
    conversation_id_map = build_conversation_id_map(flows)
    localization_index = build_localization_index(Map.get(project_data, :localization))

    result = %{
      "version" => "1.0",
      "author" => "Storyarn",
      "description" => database_description(project, opts),
      "globalUserScript" => "",
      "emphasisSettings" => default_emphasis_settings(),
      "actors" => build_actors(sheets, actor_id_map),
      "items" => [],
      "locations" => [],
      "variables" => build_variables(variables),
      "conversations" => build_conversations(flows, actor_id_map, conversation_id_map, localization_index),
      "syncInfo" => sync_info(),
      "templateJson" => template_json()
    }

    json_opts = if opts.pretty_print, do: [pretty: true], else: []
    {:ok, Jason.encode!(result, json_opts)}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Localization
  # ---------------------------------------------------------------------------

  defp build_localization_index(%{languages: languages, strings: strings}) do
    source_locale_codes = source_locale_codes(languages)

    strings
    |> Enum.reject(fn text -> MapSet.member?(source_locale_codes, localization_attr(text, :locale_code)) end)
    |> Enum.filter(&(localized_translation(&1) != ""))
    |> Enum.group_by(fn text ->
      {
        localization_attr(text, :source_type),
        text |> localization_attr(:source_id) |> to_string(),
        localization_attr(text, :source_field)
      }
    end)
  end

  defp build_localization_index(_localization), do: %{}

  defp source_locale_codes(languages) do
    languages
    |> Enum.filter(&(localization_attr(&1, :is_source) == true))
    |> MapSet.new(&localization_attr(&1, :locale_code))
  end

  defp localized_text_fields(plan, node, source_field, field_title) do
    plan.localization_index
    |> Map.get({"flow_node", to_string(node.id), source_field}, [])
    |> Enum.sort_by(&localization_attr(&1, :locale_code))
    |> Enum.map(fn text ->
      localization_field("#{field_title} #{localization_attr(text, :locale_code)}", localized_translation(text))
    end)
  end

  defp localized_translation(text) do
    text
    |> localization_attr(:translated_text)
    |> case do
      nil -> ""
      value -> value |> to_string() |> Helpers.strip_html()
    end
  end

  defp localization_attr(record, field) do
    case Map.fetch(record, field) do
      {:ok, value} -> value
      :error -> Map.get(record, to_string(field))
    end
  end

  # ---------------------------------------------------------------------------
  # Actors
  # ---------------------------------------------------------------------------

  defp build_actor_id_map(sheets) do
    sheets
    |> Enum.with_index(@player_actor_id + 1)
    |> Map.new(fn {sheet, idx} -> {to_string(sheet.id), idx} end)
  end

  defp build_actors(sheets, actor_id_map) do
    [player_actor() | Enum.map(sheets, &sheet_actor(&1, actor_id_map))]
  end

  defp player_actor do
    actor_asset(@player_actor_id, [
      text_field("Name", "Player"),
      files_field("Pictures", "[]"),
      text_field("Description", ""),
      boolean_field("IsPlayer", true),
      text_field("Display Name", "Player"),
      text_field("Storyarn Actor Kind", "synthetic_player")
    ])
  end

  defp sheet_actor(sheet, actor_id_map) do
    actor_asset(actor_id_map[to_string(sheet.id)], [
      text_field("Name", sheet.name),
      files_field("Pictures", "[]"),
      text_field("Description", ""),
      boolean_field("IsPlayer", false),
      text_field("Display Name", sheet.name),
      text_field("Storyarn Sheet ID", sheet.id),
      text_field("Storyarn Shortcut", sheet.shortcut)
    ])
  end

  defp actor_asset(id, fields) do
    %{
      "id" => id,
      "fields" => fields,
      "portrait" => %{"instanceID" => 0},
      "spritePortrait" => %{"instanceID" => 0},
      "alternatePortraits" => [],
      "spritePortraits" => []
    }
  end

  # ---------------------------------------------------------------------------
  # Variables
  # ---------------------------------------------------------------------------

  defp build_variables(variables) do
    variables
    |> Enum.with_index(1)
    |> Enum.map(fn {var, id} ->
      asset(id, [
        text_field("Name", var.full_ref),
        text_field("Initial Value", format_initial_value(var.default)),
        text_field("Description", ""),
        text_field("Storyarn Sheet Shortcut", var.sheet_shortcut),
        text_field("Storyarn Variable Name", var.variable_name),
        text_field("Storyarn Variable Type", var.type)
      ])
    end)
  end

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  defp build_conversation_id_map(flows) do
    flows
    |> Enum.with_index(1)
    |> Map.new(fn {flow, idx} -> {to_string(flow.id), idx} end)
  end

  defp build_conversations(flows, actor_id_map, conversation_id_map, localization_index) do
    root_entry_id_map = build_root_entry_id_map(flows)
    flow_id_by_shortcut = FlowControlResolver.flow_id_by_shortcut(flows)

    Enum.map(flows, fn flow ->
      conversation_id = conversation_id_map[to_string(flow.id)]
      default_conversant = default_conversant_id(flow, actor_id_map)

      entries =
        build_dialogue_entries(flow, conversation_id, actor_id_map, default_conversant, %{
          conversation_id_map: conversation_id_map,
          flow_id_by_shortcut: flow_id_by_shortcut,
          root_entry_id_map: root_entry_id_map,
          localization_index: localization_index
        })

      %{
        "id" => conversation_id,
        "fields" => [
          text_field("Title", flow.name),
          text_field("Description", flow.description || ""),
          actor_ref_field("Actor", @player_actor_id),
          actor_ref_field("Conversant", default_conversant),
          text_field("Storyarn Flow ID", flow.id),
          text_field("Storyarn Shortcut", flow.shortcut)
        ],
        "overrideSettings" => %{},
        "dialogueEntries" => entries,
        "canvasScrollPosition" => %{"x" => 0.0, "y" => 0.0},
        "canvasZoom" => 1.0
      }
    end)
  end

  defp build_root_entry_id_map(flows) do
    Map.new(flows, fn flow ->
      {to_string(flow.id), FlowControlResolver.root_entry_index(flow, &export_dialogue_entry_node?/1)}
    end)
  end

  defp default_conversant_id(flow, actor_id_map) do
    speaker_id =
      Enum.find_value(flow.nodes, fn node ->
        data = node.data || %{}
        speaker_sheet_id = data["speaker_sheet_id"]

        if speaker_sheet_id in [nil, ""] do
          nil
        else
          actor_id_map[to_string(speaker_sheet_id)]
        end
      end)

    speaker_id || first_sheet_actor_id(actor_id_map) || 0
  end

  defp first_sheet_actor_id(actor_id_map) do
    actor_id_map
    |> Map.values()
    |> Enum.sort()
    |> List.first()
  end

  # ---------------------------------------------------------------------------
  # Dialogue entries
  # ---------------------------------------------------------------------------

  defp build_dialogue_entries(flow, conversation_id, actor_id_map, default_conversant, references) do
    plan = build_entry_plan(flow, conversation_id, actor_id_map, default_conversant, references)

    Enum.flat_map(plan.entry_nodes, fn node ->
      [build_node_entry(node, plan)] ++
        build_response_entries(node, plan) ++
        build_condition_branch_entries(node, plan)
    end)
  end

  defp build_entry_plan(flow, conversation_id, actor_id_map, default_conversant, references) do
    nodes = flow.nodes || []
    entry_nodes = Enum.filter(nodes, &export_dialogue_entry_node?/1)
    conn_graph = Helpers.connection_graph(flow)
    nodes_by_id = Map.new(nodes, &{&1.id, &1})
    sequence_nodes_by_id = nodes |> Enum.filter(&(&1.type == "sequence")) |> Map.new(&{&1.id, &1})

    node_entry_ids =
      entry_nodes
      |> Enum.with_index(1)
      |> Map.new(fn {node, id} -> {node.id, id} end)

    {response_entry_ids, response_next_id} =
      Enum.reduce(entry_nodes, {%{}, length(entry_nodes) + 1}, fn node, {ids, next_id} ->
        node
        |> dialogue_responses()
        |> Enum.reduce({ids, next_id}, fn response, {response_ids, response_next_id} ->
          key = {node.id, to_string(response["id"])}
          {Map.put(response_ids, key, response_next_id), response_next_id + 1}
        end)
      end)

    {condition_branch_entry_ids, _next_id} =
      allocate_condition_branch_entry_ids(entry_nodes, conn_graph, response_next_id)

    %{
      conversation_id: conversation_id,
      actor_id_map: actor_id_map,
      default_conversant: default_conversant,
      entry_nodes: entry_nodes,
      node_entry_ids: node_entry_ids,
      response_entry_ids: response_entry_ids,
      condition_branch_entry_ids: condition_branch_entry_ids,
      conn_graph: conn_graph,
      nodes_by_id: nodes_by_id,
      sequence_nodes_by_id: sequence_nodes_by_id,
      conversation_id_map: Map.fetch!(references, :conversation_id_map),
      flow_id_by_shortcut: Map.fetch!(references, :flow_id_by_shortcut),
      root_entry_id_map: Map.fetch!(references, :root_entry_id_map),
      localization_index: Map.fetch!(references, :localization_index)
    }
  end

  defp export_dialogue_entry_node?(%{type: type}) when type in ["annotation", "sequence"], do: false
  defp export_dialogue_entry_node?(_node), do: true

  defp allocate_condition_branch_entry_ids(nodes, conn_graph, next_id) do
    Enum.reduce(nodes, {%{}, next_id}, fn node, {ids, next_entry_id} ->
      node
      |> condition_branches(conn_graph)
      |> Enum.reduce({ids, next_entry_id}, fn branch, {branch_ids, branch_next_id} ->
        {Map.put(branch_ids, {node.id, branch.pin}, branch_next_id), branch_next_id + 1}
      end)
    end)
  end

  defp build_node_entry(node, plan) do
    data = node.data || %{}
    entry_id = Map.fetch!(plan.node_entry_ids, node.id)
    fields = node_fields(node, plan)

    dialogue_entry(%{
      id: entry_id,
      conversation_id: plan.conversation_id,
      fields: fields,
      is_root: node.type == "entry",
      is_group: node.type in ["entry", "hub", "sequence"],
      outgoing_links: node_outgoing_links(node, entry_id, plan),
      conditions_string: node_conditions_string(node.type, data),
      user_script: node_user_script(node.type, data),
      canvas_rect: canvas_rect(node)
    })
  end

  defp node_fields(%{type: "entry"} = node, plan) do
    base_entry_fields(node, plan, %{
      title: "<START>",
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: "",
      sequence: "",
      description: ""
    })
  end

  defp node_fields(%{type: "dialogue"} = node, plan) do
    data = node.data || %{}
    actor_id = resolve_actor_id(data, plan.actor_id_map, plan.default_conversant)

    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: actor_id,
      conversant_id: @player_actor_id,
      menu_text: Helpers.strip_html(data["menu_text"] || ""),
      dialogue_text: Helpers.dialogue_text(data),
      sequence: "",
      description: Helpers.strip_html(data["stage_directions"] || "")
    }) ++
      localized_text_fields(plan, node, "menu_text", "Menu Text") ++
      localized_text_fields(plan, node, "text", "Dialogue Text") ++
      [
        text_field("Storyarn Localization ID", data["localization_id"] || ""),
        text_field("Storyarn Technical ID", data["technical_id"] || "")
      ]
  end

  defp node_fields(%{type: "exit"} = node, plan) do
    data = node.data || %{}

    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: data["label"] || "",
      sequence: "",
      description: ""
    }) ++
      [
        text_field("Storyarn Exit Mode", data["exit_mode"] || "terminal"),
        text_field("Storyarn Outcome Tags", Enum.join(data["outcome_tags"] || [], ",")),
        text_field("Storyarn Outcome Color", data["outcome_color"] || ""),
        text_field("Storyarn Referenced Flow ID", data["referenced_flow_id"] || "")
      ]
  end

  defp node_fields(%{type: "hub"} = node, plan) do
    data = node.data || %{}

    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: "",
      sequence: "",
      description: data["label"] || ""
    }) ++
      [
        text_field("Storyarn Hub ID", data["hub_id"] || ""),
        text_field("Storyarn Hub Color", data["color"] || "")
      ]
  end

  defp node_fields(%{type: "jump"} = node, plan) do
    data = node.data || %{}
    target_hub_id = FlowControlResolver.target_hub_id(data)

    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: "",
      sequence: "",
      description: ""
    }) ++
      [
        text_field("Storyarn Target Hub ID", target_hub_id || ""),
        text_field("Storyarn Target Flow Shortcut", data["target_flow_shortcut"] || "")
      ]
  end

  defp node_fields(%{type: "subflow"} = node, plan) do
    data = node.data || %{}

    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: "",
      sequence: "",
      description: data["referenced_flow_name"] || ""
    }) ++
      [
        text_field("Storyarn Referenced Flow ID", data["referenced_flow_id"] || ""),
        text_field(
          "Storyarn Referenced Flow Shortcut",
          data["referenced_flow_shortcut"] || data["flow_shortcut"] || ""
        )
      ]
  end

  defp node_fields(node, plan) do
    base_entry_fields(node, plan, %{
      title: entry_title(node),
      actor_id: @player_actor_id,
      conversant_id: plan.default_conversant,
      menu_text: "",
      dialogue_text: "",
      sequence: "",
      description: ""
    })
  end

  defp base_entry_fields(node, plan, attrs) do
    [
      text_field("Title", attrs.title),
      text_field("Description", attrs.description),
      actor_ref_field("Actor", attrs.actor_id),
      actor_ref_field("Conversant", attrs.conversant_id),
      text_field("Menu Text", attrs.menu_text),
      text_field("Dialogue Text", attrs.dialogue_text),
      text_field("Sequence", attrs.sequence),
      text_field("Storyarn Node ID", node.id),
      text_field("Storyarn Node Type", node.type)
    ] ++ sequence_membership_fields(node, plan)
  end

  defp sequence_membership_fields(node, plan) do
    sequence_path = sequence_path(node, plan)
    direct_sequence = List.last(sequence_path)

    [
      text_field("Storyarn Sequence ID", direct_sequence && direct_sequence.id),
      text_field("Storyarn Sequence Name", sequence_name(direct_sequence)),
      text_field("Storyarn Sequence Path", Enum.map_join(sequence_path, " / ", &sequence_name/1)),
      text_field("Storyarn Sequence Depth", length(sequence_path))
    ]
  end

  defp sequence_path(%{parent_id: nil}, _plan), do: []
  defp sequence_path(%{parent_id: parent_id}, plan), do: collect_sequence_path(parent_id, plan, MapSet.new())

  defp collect_sequence_path(nil, _plan, _visited), do: []

  defp collect_sequence_path(parent_id, plan, visited) do
    if MapSet.member?(visited, parent_id) do
      []
    else
      case Map.get(plan.sequence_nodes_by_id, parent_id) do
        nil ->
          []

        sequence ->
          collect_sequence_path(sequence.parent_id, plan, MapSet.put(visited, parent_id)) ++ [sequence]
      end
    end
  end

  defp sequence_name(nil), do: ""

  defp sequence_name(%{sequence_config: %{name: name}}) when is_binary(name) and name != "" do
    name
  end

  defp sequence_name(%{data: %{"name" => name}}) when is_binary(name) and name != "" do
    name
  end

  defp sequence_name(%{id: id}), do: "Sequence #{id}"

  defp build_response_entries(%{type: "dialogue"} = node, plan) do
    data = node.data || %{}
    dialogue_actor_id = resolve_actor_id(data, plan.actor_id_map, plan.default_conversant)

    node
    |> dialogue_responses()
    |> Enum.map(fn response ->
      response_id = response_entry_id!(plan, node, response)
      menu_text = response["menu_text"] || response["text"] || ""
      dialogue_text = response["text"] || ""

      localized_response_fields =
        localized_text_fields(plan, node, "response.#{response["id"]}.text", "Menu Text") ++
          localized_text_fields(plan, node, "response.#{response["id"]}.text", "Dialogue Text")

      dialogue_entry(%{
        id: response_id,
        conversation_id: plan.conversation_id,
        fields:
          [
            text_field("Title", Helpers.strip_html(menu_text)),
            text_field("Description", ""),
            actor_ref_field("Actor", @player_actor_id),
            actor_ref_field("Conversant", dialogue_actor_id),
            text_field("Menu Text", Helpers.strip_html(menu_text)),
            text_field("Dialogue Text", Helpers.strip_html(dialogue_text)),
            text_field("Sequence", ""),
            text_field("Storyarn Node ID", node.id),
            text_field("Storyarn Node Type", "response"),
            text_field("Storyarn Response ID", response["id"])
          ] ++ localized_response_fields,
        is_root: false,
        is_group: false,
        outgoing_links: response_outgoing_links(node, response, response_id, plan),
        conditions_string: maybe_transpile_condition(response["condition"]),
        user_script: response_user_script(response),
        canvas_rect: response_canvas_rect(node, response_id)
      })
    end)
  end

  defp build_response_entries(_node, _plan), do: []

  defp build_condition_branch_entries(%{type: "condition"} = node, plan) do
    node
    |> condition_branches(plan)
    |> Enum.map(&condition_branch_entry(node, &1, plan))
  end

  defp build_condition_branch_entries(_node, _plan), do: []

  defp condition_branch_entry(node, branch, plan) do
    branch_entry_id = condition_branch_entry_id!(plan, node, branch.pin)

    dialogue_entry(%{
      id: branch_entry_id,
      conversation_id: plan.conversation_id,
      fields: [
        text_field("Title", "Condition: #{branch.label}"),
        text_field("Description", ""),
        actor_ref_field("Actor", @player_actor_id),
        actor_ref_field("Conversant", plan.default_conversant),
        text_field("Menu Text", ""),
        text_field("Dialogue Text", ""),
        text_field("Sequence", ""),
        text_field("Storyarn Node ID", node.id),
        text_field("Storyarn Node Type", "condition_branch"),
        text_field("Storyarn Condition Branch Pin", branch.pin),
        text_field("Storyarn Condition Branch Label", branch.label)
      ],
      is_root: false,
      is_group: false,
      outgoing_links: condition_branch_outgoing_links(node, branch, branch_entry_id, plan),
      conditions_string: branch.conditions_string,
      user_script: "",
      canvas_rect: condition_branch_canvas_rect(node, branch_entry_id)
    })
  end

  defp dialogue_entry(attrs) do
    %{
      "id" => attrs.id,
      "fields" => attrs.fields,
      "conversationID" => attrs.conversation_id,
      "isRoot" => attrs.is_root,
      "isGroup" => attrs.is_group,
      "nodeColor" => "",
      "delaySimStatus" => false,
      "falseConditionAction" => "Block",
      "conditionPriority" => @normal_priority,
      "outgoingLinks" => attrs.outgoing_links,
      "conditionsString" => attrs.conditions_string,
      "userScript" => attrs.user_script,
      "onExecute" => %{"m_PersistentCalls" => %{"m_Calls" => []}},
      "canvasRect" => attrs.canvas_rect
    }
  end

  defp node_outgoing_links(%{type: "dialogue"} = node, entry_id, plan) do
    responses = dialogue_responses(node)

    if responses == [] do
      outgoing_target_links(node.id, entry_id, plan)
    else
      Enum.map(responses, fn response ->
        outgoing_link(
          plan.conversation_id,
          entry_id,
          plan.conversation_id,
          response_entry_id!(plan, node, response)
        )
      end)
    end
  end

  defp node_outgoing_links(%{type: "condition"} = node, entry_id, plan) do
    node
    |> condition_branches(plan)
    |> Enum.map(fn branch ->
      outgoing_link(
        plan.conversation_id,
        entry_id,
        plan.conversation_id,
        condition_branch_entry_id!(plan, node, branch.pin)
      )
    end)
  end

  defp node_outgoing_links(%{type: "jump"} = node, entry_id, plan) do
    case jump_destination(node, plan) do
      {:same_conversation, destination_entry_id} ->
        [
          outgoing_link(
            plan.conversation_id,
            entry_id,
            plan.conversation_id,
            destination_entry_id
          )
        ]

      {:other_conversation, destination_conversation_id, destination_entry_id} ->
        [outgoing_link(plan.conversation_id, entry_id, destination_conversation_id, destination_entry_id)]

      nil ->
        []
    end
  end

  defp node_outgoing_links(%{type: "subflow"} = node, entry_id, plan) do
    node
    |> Map.get(:data, %{})
    |> referenced_flow_link(entry_id, plan)
  end

  defp node_outgoing_links(%{type: "exit"} = node, entry_id, plan) do
    data = node.data || %{}

    if data["exit_mode"] == "flow_reference" do
      referenced_flow_link(data, entry_id, plan)
    else
      []
    end
  end

  defp node_outgoing_links(node, entry_id, plan) do
    outgoing_target_links(node.id, entry_id, plan)
  end

  defp jump_destination(%{data: data}, plan) do
    data = data || %{}

    cond do
      flow_id = target_flow_id(data, plan) ->
        other_conversation_destination(flow_id, plan)

      hub_id = FlowControlResolver.target_hub_id(data) ->
        same_conversation_hub_destination(hub_id, plan)

      true ->
        nil
    end
  end

  defp same_conversation_hub_destination(hub_id, plan) do
    case FlowControlResolver.find_hub_by_hub_id(plan.nodes_by_id, hub_id) do
      nil ->
        nil

      hub ->
        {:same_conversation, Map.fetch!(plan.node_entry_ids, hub.id)}
    end
  end

  defp referenced_flow_link(data, entry_id, plan) do
    data
    |> target_flow_id(plan)
    |> other_conversation_destination(plan)
    |> case do
      {:other_conversation, destination_conversation_id, destination_entry_id} ->
        [outgoing_link(plan.conversation_id, entry_id, destination_conversation_id, destination_entry_id)]

      nil ->
        []
    end
  end

  defp other_conversation_destination(nil, _plan), do: nil

  defp other_conversation_destination(flow_id, plan) do
    with destination_conversation_id when not is_nil(destination_conversation_id) <-
           plan.conversation_id_map[to_string(flow_id)],
         destination_entry_id when not is_nil(destination_entry_id) <- plan.root_entry_id_map[to_string(flow_id)] do
      {:other_conversation, destination_conversation_id, destination_entry_id}
    else
      _ -> nil
    end
  end

  defp target_flow_id(data, plan) do
    FlowControlResolver.referenced_flow_id(data, plan.flow_id_by_shortcut)
  end

  defp response_outgoing_links(node, response, response_entry_id, plan) do
    response_id = to_string(response["id"])
    response_pins = [response_id, "response_#{response_id}"]

    plan.conn_graph
    |> Map.get(node.id, [])
    |> Enum.filter(fn {_target_id, source_pin, _conn} -> source_pin in response_pins end)
    |> target_links(response_entry_id, plan)
  end

  defp condition_branch_outgoing_links(node, branch, branch_entry_id, plan) do
    plan.conn_graph
    |> Map.get(node.id, [])
    |> Enum.filter(fn {_target_id, source_pin, _conn} -> source_pin == branch.pin end)
    |> target_links(branch_entry_id, plan)
  end

  defp outgoing_target_links(node_id, entry_id, plan) do
    plan.conn_graph
    |> Map.get(node_id, [])
    |> target_links(entry_id, plan)
  end

  defp target_links(targets, origin_entry_id, plan) do
    targets
    |> Enum.map(fn {target_id, _source_pin, _conn} ->
      case Map.fetch(plan.node_entry_ids, target_id) do
        {:ok, destination_entry_id} ->
          outgoing_link(plan.conversation_id, origin_entry_id, plan.conversation_id, destination_entry_id)

        :error ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp outgoing_link(origin_conversation_id, origin_dialogue_id, destination_conversation_id, destination_dialogue_id) do
    %{
      "originConversationID" => origin_conversation_id,
      "originDialogueID" => origin_dialogue_id,
      "destinationConversationID" => destination_conversation_id,
      "destinationDialogueID" => destination_dialogue_id,
      "isConnector" => false,
      "priority" => @normal_priority
    }
  end

  # ---------------------------------------------------------------------------
  # Condition branch helpers
  # ---------------------------------------------------------------------------

  defp condition_branches(%{type: "condition"} = node, %{conn_graph: conn_graph}) do
    condition_branches(node, conn_graph)
  end

  defp condition_branches(%{type: "condition", data: data, id: node_id}, conn_graph) do
    data = data || %{}
    targets_by_pin = targets_by_pin(conn_graph, node_id)

    if data["switch_mode"] == true do
      switch_condition_branches(data, targets_by_pin)
    else
      boolean_condition_branches(data, targets_by_pin)
    end
  end

  defp condition_branches(_node, _conn_graph_or_plan), do: []

  defp targets_by_pin(conn_graph, node_id) do
    conn_graph
    |> Map.get(node_id, [])
    |> Enum.group_by(fn {_target_id, source_pin, _conn} -> source_pin end)
  end

  defp boolean_condition_branches(data, targets_by_pin) do
    condition = condition_to_lua(data["condition"])

    [
      {"true", "True", condition},
      {"false", "False", negate_condition(condition)}
    ]
    |> Enum.filter(fn {pin, _label, _condition} -> Map.has_key?(targets_by_pin, pin) end)
    |> Enum.map(fn {pin, label, conditions_string} ->
      %{pin: pin, label: label, conditions_string: conditions_string}
    end)
  end

  defp switch_condition_branches(data, targets_by_pin) do
    case_defs = FlowControlResolver.switch_case_defs(data["condition"])
    case_pins = MapSet.new(Enum.map(case_defs, & &1["id"]))

    explicit_branches =
      case_defs
      |> Enum.filter(&Map.has_key?(targets_by_pin, &1["id"]))
      |> Enum.map(fn case_def ->
        %{
          pin: case_def["id"],
          label: case_def["label"],
          conditions_string: condition_to_lua(case_def["condition"])
        }
      end)

    fallback_branches =
      targets_by_pin
      |> Map.keys()
      |> Enum.reject(&(&1 == "default" or MapSet.member?(case_pins, &1)))
      |> Enum.sort()
      |> Enum.map(&%{pin: &1, label: &1, conditions_string: ""})

    default_branch =
      if Map.has_key?(targets_by_pin, "default") do
        [
          %{
            pin: "default",
            label: "Default",
            conditions_string: default_switch_condition(explicit_branches)
          }
        ]
      else
        []
      end

    explicit_branches ++ fallback_branches ++ default_branch
  end

  defp default_switch_condition(branches) do
    branches
    |> Enum.map(& &1.conditions_string)
    |> Enum.reject(&(&1 == ""))
    |> negate_any_condition()
  end

  defp condition_to_lua(raw_condition) do
    raw_condition
    |> normalize_condition()
    |> maybe_transpile_condition()
  end

  defp normalize_condition(raw_condition) do
    case Helpers.extract_condition(raw_condition) do
      %{"blocks" => _blocks} = condition ->
        condition

      %{"rules" => rules} = condition when is_list(rules) ->
        logic = condition["logic"] || "all"

        %{
          "logic" => "all",
          "blocks" => [%{"type" => "block", "logic" => logic, "rules" => rules}]
        }

      other ->
        other
    end
  end

  defp negate_condition(""), do: ""
  defp negate_condition(condition), do: "not (#{condition})"

  defp negate_any_condition([]), do: ""
  defp negate_any_condition([condition]), do: negate_condition(condition)

  defp negate_any_condition(conditions) do
    joined = Enum.map_join(conditions, " or ", &"(#{&1})")

    "not (#{joined})"
  end

  # ---------------------------------------------------------------------------
  # Entry helpers
  # ---------------------------------------------------------------------------

  defp entry_title(%{type: "dialogue", data: data, id: id}) do
    data = data || %{}
    data["technical_id"] || data["localization_id"] || "Dialogue #{id}"
  end

  defp entry_title(%{type: "exit", data: data, id: id}) do
    data = data || %{}
    data["label"] || data["technical_id"] || "Exit #{id}"
  end

  defp entry_title(%{type: "hub", data: data, id: id}) do
    data = data || %{}
    data["label"] || data["hub_id"] || "Hub #{id}"
  end

  defp entry_title(%{type: type, id: id}), do: "#{String.capitalize(type)} #{id}"

  defp dialogue_responses(%{data: data}) when is_map(data), do: Helpers.dialogue_responses(data)
  defp dialogue_responses(_node), do: []

  defp response_entry_id!(plan, node, response) do
    Map.fetch!(plan.response_entry_ids, {node.id, to_string(response["id"])})
  end

  defp condition_branch_entry_id!(plan, node, pin) do
    Map.fetch!(plan.condition_branch_entry_ids, {node.id, pin})
  end

  defp response_user_script(response) do
    case response["instruction_assignments"] do
      [_ | _] = assignments -> transpile_or_empty(assignments, :unity, :instruction)
      _ -> ""
    end
  end

  defp node_conditions_string("dialogue", data), do: maybe_transpile_condition(data["condition"])
  defp node_conditions_string(_type, _data), do: ""

  defp node_user_script("instruction", data) do
    data
    |> Helpers.extract_assignments()
    |> transpile_or_empty(:unity, :instruction)
  end

  defp node_user_script(_type, _data), do: ""

  defp resolve_actor_id(data, actor_id_map, fallback) do
    case data["speaker_sheet_id"] do
      nil -> fallback
      "" -> fallback
      id -> actor_id_map[to_string(id)] || fallback
    end
  end

  defp canvas_rect(node) do
    %{
      "serializedVersion" => "2",
      "x" => number_or_zero(node.position_x),
      "y" => number_or_zero(node.position_y),
      "width" => @entry_width,
      "height" => @entry_height
    }
  end

  defp response_canvas_rect(node, response_id) do
    base = canvas_rect(node)

    base
    |> Map.put("x", base["x"] + 220.0)
    |> Map.put("y", base["y"] + response_id * 40.0)
  end

  defp condition_branch_canvas_rect(node, branch_entry_id) do
    base = canvas_rect(node)

    base
    |> Map.put("x", base["x"] + 220.0)
    |> Map.put("y", base["y"] + branch_entry_id * 40.0)
  end

  defp number_or_zero(value) when is_number(value), do: value / 1
  defp number_or_zero(_value), do: 0.0

  # ---------------------------------------------------------------------------
  # Dialogue System field helpers
  # ---------------------------------------------------------------------------

  defp asset(id, fields), do: %{"id" => id, "fields" => fields}

  defp text_field(title, value), do: field(title, value, @text_type, @text_type_string)
  defp boolean_field(title, value), do: field(title, boolean_string(value), @boolean_type, @boolean_type_string)
  defp files_field(title, value), do: field(title, value, @files_type, @files_type_string)
  defp localization_field(title, value), do: field(title, value, @localization_type, @localization_type_string)
  defp actor_ref_field(title, value), do: field(title, value, @actor_type, @actor_type_string)

  defp field(title, value, type, type_string) do
    %{
      "title" => title,
      "value" => field_value(value),
      "type" => type,
      "typeString" => type_string
    }
  end

  defp field_value(nil), do: ""
  defp field_value(value) when is_binary(value), do: value
  defp field_value(value) when is_integer(value), do: Integer.to_string(value)
  defp field_value(value) when is_float(value), do: Float.to_string(value)
  defp field_value(value) when is_boolean(value), do: boolean_string(value)
  defp field_value(value) when is_atom(value), do: Atom.to_string(value)
  defp field_value(value), do: to_string(value)

  defp boolean_string(true), do: "True"
  defp boolean_string(false), do: "False"
  defp boolean_string(_), do: "False"

  defp format_initial_value(true), do: "True"
  defp format_initial_value(false), do: "False"
  defp format_initial_value(nil), do: ""
  defp format_initial_value(value) when is_binary(value), do: value
  defp format_initial_value(value), do: to_string(value)

  # ---------------------------------------------------------------------------
  # Envelope helpers
  # ---------------------------------------------------------------------------

  defp database_description(nil, opts), do: "Exported from Storyarn #{opts.version}"

  defp database_description(project, opts) do
    "Exported from Storyarn #{opts.version}: #{project.name}"
  end

  defp default_emphasis_settings do
    [
      emphasis_color(1.0, 1.0, 1.0),
      emphasis_color(1.0, 0.0, 0.0),
      emphasis_color(0.0, 1.0, 0.0),
      emphasis_color(0.0, 0.0, 1.0)
    ]
  end

  defp emphasis_color(r, g, b) do
    %{
      "color" => %{"r" => r, "g" => g, "b" => b, "a" => 1.0},
      "bold" => false,
      "italic" => false,
      "underline" => false
    }
  end

  defp sync_info do
    %{
      "syncActors" => false,
      "syncItems" => false,
      "syncLocations" => false,
      "syncVariables" => false,
      "syncActorsDatabase" => %{"instanceID" => 0},
      "syncItemsDatabase" => %{"instanceID" => 0},
      "syncLocationsDatabase" => %{"instanceID" => 0},
      "syncVariablesDatabase" => %{"instanceID" => 0}
    }
  end

  defp template_json do
    Jason.encode!(%{
      "treatItemsAsQuests" => true,
      "actorFields" => [
        text_field("Name", ""),
        files_field("Pictures", "[]"),
        text_field("Description", ""),
        boolean_field("IsPlayer", false),
        text_field("Display Name", "")
      ],
      "variableFields" => [text_field("Name", ""), text_field("Initial Value", ""), text_field("Description", "")],
      "conversationFields" => [
        text_field("Title", ""),
        text_field("Description", ""),
        actor_ref_field("Actor", 0),
        actor_ref_field("Conversant", 0)
      ],
      "dialogueEntryFields" => [
        text_field("Title", ""),
        text_field("Description", ""),
        actor_ref_field("Actor", 0),
        actor_ref_field("Conversant", 0),
        text_field("Menu Text", ""),
        text_field("Dialogue Text", ""),
        text_field("Sequence", "")
      ],
      "actorPrimaryFieldTitles" => [],
      "itemPrimaryFieldTitles" => [],
      "questPrimaryFieldTitles" => [],
      "locationPrimaryFieldTitles" => [],
      "variablePrimaryFieldTitles" => [],
      "conversationPrimaryFieldTitles" => [],
      "dialogueEntryPrimaryFieldTitles" => []
    })
  end

  # ---------------------------------------------------------------------------
  # Expressions
  # ---------------------------------------------------------------------------

  defp maybe_transpile_condition(nil), do: ""
  defp maybe_transpile_condition(""), do: ""

  defp maybe_transpile_condition(raw_condition) do
    case ExpressionTranspiler.transpile_condition(raw_condition, :unity) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end

  defp transpile_or_empty(nil, _engine, _type), do: ""
  defp transpile_or_empty([], _engine, _type), do: ""

  defp transpile_or_empty(data, engine, :instruction) do
    case ExpressionTranspiler.transpile_instruction(data, engine) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end
end
