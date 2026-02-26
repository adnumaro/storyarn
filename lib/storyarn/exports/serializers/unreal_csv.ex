defmodule Storyarn.Exports.Serializers.UnrealCSV do
  @moduledoc """
  Unreal Engine DataTable CSV serializer.

  Produces multiple CSV files importable as Unreal DataTables, plus a metadata
  JSON file with the graph structure that CSV can't represent.

  ## Output

  Returns `{:ok, [{filename, content}, ...]}` with:
  - `DT_DialogueLines.csv` — all dialogue/node rows
  - `DT_Characters.csv` — character data from sheets
  - `DT_Variables.csv` — variable definitions
  - `Conversations.json` — flow graph structure metadata
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.{ExportOptions, ExpressionTranspiler}
  alias Storyarn.Exports.Serializers.Helpers

  @impl true
  def content_type, do: "text/csv"

  @impl true
  def file_extension, do: "csv"

  @impl true
  def format_label, do: "Unreal Engine (CSV)"

  @impl true
  def supported_sections, do: [:flows, :sheets]

  @impl true
  def serialize(project_data, %ExportOptions{} = _opts) do
    sheets = project_data.sheets || []
    flows = project_data.flows || []
    variables = Helpers.collect_variables(sheets)
    speaker_map = Helpers.build_speaker_map(sheets)

    dialogue_csv = build_dialogue_csv(flows, speaker_map)
    characters_csv = build_characters_csv(sheets)
    variables_csv = build_variables_csv(variables)
    metadata = build_metadata(flows, sheets, variables, speaker_map)

    {:ok,
     [
       {"DT_DialogueLines.csv", dialogue_csv},
       {"DT_Characters.csv", characters_csv},
       {"DT_Variables.csv", variables_csv},
       {"Conversations.json", Jason.encode!(metadata, pretty: true)}
     ]}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Dialogue Lines CSV
  # ---------------------------------------------------------------------------

  defp build_dialogue_csv(flows, speaker_map) do
    headers = [
      "Name",
      "ConversationId",
      "NodeType",
      "SpeakerId",
      "Text",
      "TextKey",
      "MenuText",
      "StageDirections",
      "Sequence",
      "NextLines",
      "Conditions",
      "UserScript"
    ]

    counter = :counters.new(1, [:atomics])

    rows =
      Enum.flat_map(flows, fn flow ->
        conv_id = Helpers.shortcut_to_identifier(flow.shortcut || flow.name || "flow_#{flow.id}")
        conn_graph = Helpers.connection_graph(flow)
        build_flow_rows(flow, conv_id, conn_graph, speaker_map, counter)
      end)

    Helpers.build_csv(headers, rows)
  end

  defp build_flow_rows(flow, conv_id, conn_graph, speaker_map, counter) do
    # Build a mapping from node_id to row name for cross-referencing
    node_row_map = build_node_row_map(flow.nodes, counter)

    Enum.flat_map(flow.nodes, fn node ->
      build_node_rows(node, conv_id, conn_graph, speaker_map, node_row_map)
    end)
  end

  defp build_node_row_map(nodes, counter) do
    Map.new(nodes, fn node ->
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)
      row_name = "DLG_#{String.pad_leading(to_string(n), 4, "0")}"
      {node.id, row_name}
    end)
  end

  defp build_node_rows(node, conv_id, conn_graph, speaker_map, node_row_map) do
    targets = Helpers.outgoing_targets(node.id, conn_graph)
    next_lines = Enum.map_join(targets, "|", fn {tid, _pin, _conn} -> node_row_map[tid] || "" end)
    data = node.data || %{}
    row_name = node_row_map[node.id] || ""

    row_context = %{data: data, conv_id: conv_id, row_name: row_name, next_lines: next_lines}
    build_typed_rows(node.type, row_context, speaker_map)
  end

  defp build_typed_rows("dialogue", ctx, speaker_map) do
    %{data: data, conv_id: conv_id, row_name: row_name, next_lines: next_lines} = ctx
    speaker = Helpers.speaker_shortcut(data, speaker_map)
    text = Helpers.dialogue_text(data)
    stage = Helpers.strip_html(data["stage_directions"] || "")
    responses = Helpers.dialogue_responses(data)
    condition = maybe_transpile_condition(data["condition"])

    main_row = [
      row_name,
      conv_id,
      "dialogue",
      speaker || "",
      text,
      String.downcase(row_name),
      data["menu_text"] || "",
      stage,
      0,
      if(responses == [], do: next_lines, else: ""),
      condition,
      ""
    ]

    response_rows = build_response_rows(responses, row_name, conv_id, next_lines)
    [main_row | response_rows]
  end

  defp build_typed_rows("condition", ctx, _speaker_map) do
    condition = Helpers.extract_condition(ctx.data["condition"])
    [simple_row(ctx, "condition", "", transpile_or_empty(condition, :unreal, :condition), "")]
  end

  defp build_typed_rows("instruction", ctx, _speaker_map) do
    assignments = Helpers.extract_assignments(ctx.data)

    [
      simple_row(
        ctx,
        "instruction",
        "",
        "",
        transpile_or_empty(assignments, :unreal, :instruction)
      )
    ]
  end

  defp build_typed_rows("hub", ctx, _speaker_map) do
    [simple_row(ctx, "hub", ctx.data["label"] || "", "", "")]
  end

  defp build_typed_rows("jump", ctx, _speaker_map) do
    target = ctx.data["hub_id"] || ctx.data["target_flow_shortcut"] || ""
    [simple_row(ctx, "jump", "", "", to_string(target))]
  end

  defp build_typed_rows("scene", ctx, _speaker_map) do
    location = ctx.data["location"] || ctx.data["slug_line"] || ""
    [simple_row(ctx, "scene", location, "", "")]
  end

  defp build_typed_rows("entry", ctx, _speaker_map) do
    [simple_row(ctx, "entry", "", "", "")]
  end

  defp build_typed_rows("exit", ctx, _speaker_map) do
    [
      [
        ctx.row_name,
        ctx.conv_id,
        "exit",
        "",
        ctx.data["technical_id"] || "",
        "",
        "",
        "",
        0,
        "",
        "",
        ""
      ]
    ]
  end

  defp build_typed_rows(_type, _ctx, _speaker_map), do: []

  defp simple_row(ctx, type, text, conditions, script) do
    [ctx.row_name, ctx.conv_id, type, "", text, "", "", "", 0, ctx.next_lines, conditions, script]
  end

  defp build_response_rows(responses, row_name, conv_id, next_lines) do
    responses
    |> Enum.with_index(1)
    |> Enum.map(fn {resp, idx} ->
      resp_name = "#{row_name}_R#{idx}"
      resp_text = Helpers.strip_html(resp["text"] || "")
      resp_condition = maybe_transpile_condition(resp["condition"])

      resp_script =
        case resp["instruction_assignments"] do
          [_ | _] = assigns -> transpile_or_empty(assigns, :unreal, :instruction)
          _ -> ""
        end

      [
        resp_name,
        conv_id,
        "response",
        "",
        resp_text,
        String.downcase(resp_name),
        Helpers.strip_html(resp["menu_text"] || resp["text"] || ""),
        "",
        0,
        next_lines,
        resp_condition,
        resp_script
      ]
    end)
  end

  defp maybe_transpile_condition(raw_condition) do
    case Helpers.extract_condition(raw_condition) do
      nil -> ""
      cond -> transpile_or_empty(cond, :unreal, :condition)
    end
  end

  # ---------------------------------------------------------------------------
  # Characters CSV
  # ---------------------------------------------------------------------------

  defp build_characters_csv(sheets) do
    headers = ["Name", "DisplayName", "ShortcutId", "Properties"]

    rows =
      Enum.map(sheets, fn sheet ->
        props =
          sheet.blocks
          |> Enum.reject(& &1.is_constant)
          |> Enum.filter(&(is_binary(&1.variable_name) and &1.variable_name != ""))
          |> Map.new(fn block ->
            {block.variable_name, Helpers.infer_default_value(block)}
          end)

        props_json = Jason.encode!(props)
        char_name = "CHAR_#{Helpers.shortcut_to_identifier(sheet.shortcut)}"

        [char_name, sheet.name, sheet.shortcut, props_json]
      end)

    Helpers.build_csv(headers, rows)
  end

  # ---------------------------------------------------------------------------
  # Variables CSV
  # ---------------------------------------------------------------------------

  defp build_variables_csv(variables) do
    headers = ["Name", "VariableId", "Type", "DefaultValue", "SheetShortcut", "VariableName"]

    rows =
      Enum.map(variables, fn var ->
        row_name = "VAR_#{Helpers.shortcut_to_identifier(var.full_ref)}"

        [
          row_name,
          var.full_ref,
          to_string(var.type),
          to_string(var.default),
          var.sheet_shortcut,
          var.variable_name
        ]
      end)

    Helpers.build_csv(headers, rows)
  end

  # ---------------------------------------------------------------------------
  # Metadata JSON
  # ---------------------------------------------------------------------------

  defp build_metadata(flows, sheets, variables, speaker_map) do
    conversations =
      Map.new(flows, fn flow ->
        conv_id =
          Helpers.shortcut_to_identifier(flow.shortcut || flow.name || "flow_#{flow.id}")

        entry = Helpers.find_entry_node(flow)
        conn_graph = Helpers.connection_graph(flow)
        nodes_meta = build_nodes_meta(flow.nodes, conn_graph)

        {conv_id,
         %{
           "name" => flow.name,
           "shortcut" => flow.shortcut,
           "start_node" => if(entry, do: to_string(entry.id), else: nil),
           "nodes" => nodes_meta
         }}
      end)

    characters =
      Map.new(sheets, fn sheet ->
        info = speaker_map[to_string(sheet.id)] || %{name: sheet.name, shortcut: sheet.shortcut}

        {Helpers.shortcut_to_identifier(sheet.shortcut),
         %{
           "display_name" => info.name,
           "shortcut" => info.shortcut
         }}
      end)

    variable_map =
      Map.new(variables, fn var ->
        {var.full_ref,
         %{
           "type" => to_string(var.type),
           "default" => var.default
         }}
      end)

    %{
      "format" => "storyarn_unreal",
      "version" => "1.0.0",
      "conversations" => conversations,
      "characters" => characters,
      "variables" => variable_map
    }
  end

  defp build_nodes_meta(nodes, conn_graph) do
    Map.new(nodes, fn node ->
      targets = Helpers.outgoing_targets(node.id, conn_graph)
      outputs = Enum.map(targets, fn {tid, _pin, _conn} -> to_string(tid) end)

      {to_string(node.id),
       %{
         "type" => node.type,
         "outputs" => outputs
       }}
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp transpile_or_empty(nil, _engine, _type), do: ""
  defp transpile_or_empty([], _engine, _type), do: ""

  defp transpile_or_empty(data, engine, :condition) do
    case ExpressionTranspiler.transpile_condition(data, engine) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end

  defp transpile_or_empty(data, engine, :instruction) do
    case ExpressionTranspiler.transpile_instruction(data, engine) do
      {:ok, expr, _} -> expr
      _ -> ""
    end
  end
end
