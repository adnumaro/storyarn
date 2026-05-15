defmodule Storyarn.Exports.Serializers.Yarn do
  @moduledoc """
  Yarn Spinner serializer.

  Produces `.yarn` text files for Yarn Spinner (Unity, Godot, GameMaker, GDevelop).
  Built-in localization support via line tags.

  ## Output

  Returns `{:ok, [{filename, content}, ...]}` with:
  - `.yarn` file(s) — single or multi-file based on flow count
  - `metadata.json` — character/variable/flow mapping
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.ExpressionTranspiler
  alias Storyarn.Exports.Serializers.GraphTraversal
  alias Storyarn.Exports.Serializers.Helpers

  @impl true
  def content_type, do: "text/plain"

  @impl true
  def file_extension, do: "yarn"

  @impl true
  def format_label, do: "Yarn Spinner (.yarn)"

  @impl true
  def supported_sections, do: [:flows, :sheets]

  @impl true
  def serialize(project_data, %ExportOptions{} = _opts) do
    sheets = project_data.sheets || []
    flows = project_data.flows || []
    variables = Helpers.collect_variables(sheets)
    speaker_map = Helpers.build_speaker_map(sheets)
    flow_shortcuts_by_id = flow_shortcuts_by_id(flows)
    detour_targets = collect_detour_targets(flows, flow_shortcuts_by_id)

    # Multi-file for >5 flows, single-file otherwise
    project_name = Helpers.shortcut_to_identifier(project_data.project.slug || "story")
    line_counter = :counters.new(1, [:atomics])

    var_decls = variable_declarations(variables)

    yarn_files =
      if length(flows) > 5 do
        serialize_multi_file(flows, var_decls, speaker_map, flow_shortcuts_by_id, detour_targets, line_counter)
      else
        serialize_single_file(
          flows,
          var_decls,
          speaker_map,
          flow_shortcuts_by_id,
          detour_targets,
          line_counter,
          project_name
        )
      end

    metadata = build_metadata(project_data.project, sheets, variables, flows)

    {:ok, yarn_files ++ [{"metadata.json", Jason.encode!(metadata, pretty: true)}]}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Multi-file / single-file strategies
  # ---------------------------------------------------------------------------

  defp serialize_multi_file(flows, var_decls, speaker_map, flow_shortcuts_by_id, detour_targets, line_counter) do
    flows
    |> Enum.with_index()
    |> Enum.map(fn {flow, idx} ->
      filename = Helpers.shortcut_to_identifier(flow.shortcut || "flow_#{flow.id}")
      decls = if idx == 0, do: var_decls, else: []
      content = flow_to_yarn(flow, decls, speaker_map, flow_shortcuts_by_id, detour_targets, line_counter)
      {"#{filename}.yarn", content}
    end)
  end

  defp serialize_single_file(
         flows,
         var_decls,
         speaker_map,
         flow_shortcuts_by_id,
         detour_targets,
         line_counter,
         project_name
       ) do
    {first_content, rest_content} =
      case flows do
        [first | rest] ->
          {
            flow_to_yarn(first, var_decls, speaker_map, flow_shortcuts_by_id, detour_targets, line_counter),
            Enum.map(rest, &flow_to_yarn(&1, [], speaker_map, flow_shortcuts_by_id, detour_targets, line_counter))
          }

        [] ->
          {"", []}
      end

    content = Enum.join([first_content | rest_content], "\n")
    [{"#{project_name}.yarn", content}]
  end

  # ---------------------------------------------------------------------------
  # Flow → Yarn node(s)
  # ---------------------------------------------------------------------------

  defp flow_to_yarn(flow, var_decls, speaker_map, flow_shortcuts_by_id, detour_targets, line_counter) do
    node_title = Helpers.shortcut_to_identifier(flow.shortcut || flow.name || "flow_#{flow.id}")
    {instructions, hub_sections} = GraphTraversal.linearize(flow)

    ctx = %{
      speaker_map: speaker_map,
      flow_shortcuts_by_id: flow_shortcuts_by_id,
      is_detour_target: MapSet.member?(detour_targets, flow.shortcut)
    }

    # Main node
    main_body = render_instructions(instructions, ctx, line_counter, 0)

    main_node =
      yarn_node(node_title, flow.name, var_decls ++ main_body)

    # Hub sections as separate Yarn nodes
    hub_nodes =
      Enum.map(hub_sections, fn {label, instrs} ->
        body = render_instructions(instrs, ctx, line_counter, 0)
        yarn_node(label, "", body)
      end)

    [main_node | hub_nodes]
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  defp yarn_node(title, _display_name, body_lines) do
    body = Enum.join(body_lines, "\n")

    """
    title: #{title}
    tags:
    ---
    #{body}
    ===
    """
  end

  # ---------------------------------------------------------------------------
  # Variable declarations
  # ---------------------------------------------------------------------------

  defp variable_declarations([]), do: []

  defp variable_declarations(variables) do
    Enum.map(variables, fn var ->
      yarn_name = Helpers.shortcut_to_identifier(var.full_ref)
      value = Helpers.format_var_declaration_value(var)
      "<<declare $#{yarn_name} = #{value}>>"
    end)
  end

  # ---------------------------------------------------------------------------
  # Instruction rendering
  # ---------------------------------------------------------------------------

  defp render_instructions(instructions, ctx, line_counter, depth) do
    render_instruction_stream(instructions, ctx, line_counter, depth)
  end

  defp render_instruction_stream([], _ctx, _line_counter, _depth), do: []

  defp render_instruction_stream([{:choices_start, _node} | rest], ctx, line_counter, depth) do
    {choice_instructions, rest} =
      Enum.split_while(rest, fn
        {:choices_end, _node} -> false
        _instruction -> true
      end)

    rest =
      case rest do
        [{:choices_end, _node} | tail] -> tail
        tail -> tail
      end

    render_choice_instructions(choice_instructions, ctx, line_counter, depth) ++
      render_instruction_stream(rest, ctx, line_counter, depth)
  end

  defp render_instruction_stream([instruction | rest], ctx, line_counter, depth) do
    render_instruction(instruction, ctx, line_counter, depth) ++
      render_instruction_stream(rest, ctx, line_counter, depth)
  end

  defp render_choice_instructions(instructions, ctx, line_counter, depth) do
    instructions
    |> choice_blocks([])
    |> Enum.flat_map(fn {choice, body} ->
      render_instruction(choice, ctx, line_counter, depth) ++
        render_instructions(body, ctx, line_counter, depth + 1)
    end)
  end

  defp choice_blocks([], acc), do: Enum.reverse(acc)

  defp choice_blocks([{:choice, _resp, _idx} = choice | rest], acc) do
    {body, rest} =
      Enum.split_while(rest, fn
        {:choice, _resp, _idx} -> false
        _instruction -> true
      end)

    choice_blocks(rest, [{choice, body} | acc])
  end

  defp choice_blocks([_instruction | rest], acc), do: choice_blocks(rest, acc)

  defp render_instruction({:dialogue, node}, ctx, line_counter, depth) do
    data = node.data || %{}
    text = data |> Helpers.dialogue_text() |> escape_yarn_text()
    speaker = Helpers.speaker_name(data, ctx.speaker_map)
    line_id = next_line_id(line_counter)

    line =
      if speaker do
        "#{indent(depth)}#{speaker}: #{text} #line:#{line_id}"
      else
        "#{indent(depth)}#{text} #line:#{line_id}"
      end

    [line]
  end

  defp render_instruction({:choices_start, _node}, _ctx, _lc, _depth), do: []

  defp render_instruction({:choice, resp, _idx}, _ctx, line_counter, depth) do
    text = (resp["text"] || resp["menu_text"] || "") |> Helpers.strip_html() |> escape_yarn_text()
    line_id = next_line_id(line_counter)
    condition = build_yarn_condition(resp["condition"])

    choice_line =
      if condition do
        "#{indent(depth)}-> #{text} <<if #{condition}>> #line:#{line_id}"
      else
        "#{indent(depth)}-> #{text} #line:#{line_id}"
      end

    assign_lines =
      case resp["instruction_assignments"] do
        [_ | _] = assignments ->
          case ExpressionTranspiler.transpile_instruction(assignments, :yarn) do
            {:ok, expr, _} when expr != "" ->
              expr |> String.split("\n") |> Enum.map(&"#{indent(depth + 1)}#{&1}")

            _ ->
              []
          end

        _ ->
          []
      end

    [choice_line | assign_lines]
  end

  defp render_instruction({:choices_end, _node}, _ctx, _lc, _depth), do: []

  defp render_instruction({:condition_start, node}, _ctx, _lc, depth) do
    data = node.data || %{}
    condition = Helpers.extract_condition(data["condition"])

    case ExpressionTranspiler.transpile_condition(condition, :yarn) do
      {:ok, expr, _} when expr != "" ->
        ["#{indent(depth)}<<if #{expr}>>"]

      _ ->
        ["#{indent(depth)}<<if true>>"]
    end
  end

  defp render_instruction({:condition_branch, _pin, _label, idx}, _ctx, _lc, depth) do
    case idx do
      0 -> []
      1 -> ["#{indent(depth)}<<else>>"]
      # Yarn only supports one <<else>> — additional branches are folded under it
      _ -> ["#{indent(depth)}// (branch #{idx})"]
    end
  end

  defp render_instruction({:condition_end, _node}, _ctx, _lc, depth) do
    ["#{indent(depth)}<<endif>>"]
  end

  defp render_instruction({:instruction, node}, _ctx, _lc, depth) do
    data = node.data || %{}
    assignments = Helpers.extract_assignments(data)

    case ExpressionTranspiler.transpile_instruction(assignments, :yarn) do
      {:ok, expr, _} when expr != "" ->
        expr |> String.split("\n") |> Enum.map(&"#{indent(depth)}#{&1}")

      _ ->
        []
    end
  end

  defp render_instruction({:subflow, node}, ctx, _lc, depth) do
    data = node.data || %{}
    target = Helpers.shortcut_to_identifier(resolve_flow_shortcut(data, ctx) || "subflow_#{node.id}")
    ["#{indent(depth)}<<detour #{target}>>"]
  end

  defp render_instruction({:jump, _node, target_label}, _ctx, _lc, depth) do
    ["#{indent(depth)}<<jump #{target_label}>>"]
  end

  defp render_instruction({:divert, target_label}, _ctx, _lc, depth) do
    ["#{indent(depth)}<<jump #{target_label}>>"]
  end

  defp render_instruction({:exit, node}, ctx, _lc, depth) do
    data = node.data || %{}

    case data["exit_mode"] do
      "flow_reference" ->
        target = Helpers.shortcut_to_identifier(resolve_flow_shortcut(data, ctx) || "unknown")
        ["#{indent(depth)}<<jump #{target}>>"]

      "caller_return" ->
        ["#{indent(depth)}<<return>>"]

      _mode ->
        [terminal_command(ctx, depth)]
    end
  end

  defp render_instruction(_, _ctx, _lc, _depth), do: []

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp escape_yarn_text(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("#", "\\#")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
  end

  defp escape_yarn_text(_), do: ""

  defp terminal_command(%{is_detour_target: true}, depth), do: "#{indent(depth)}<<return>>"
  defp terminal_command(_ctx, depth), do: "#{indent(depth)}<<stop>>"

  defp flow_shortcuts_by_id(flows) do
    Map.new(flows, fn flow -> {to_string(flow.id), flow.shortcut} end)
  end

  defp collect_detour_targets(flows, flow_shortcuts_by_id) do
    flows
    |> Enum.flat_map(fn flow ->
      (flow.nodes || [])
      |> Enum.filter(&(&1.type == "subflow"))
      |> Enum.map(&resolve_flow_shortcut(&1.data || %{}, flow_shortcuts_by_id))
      |> Enum.reject(&blank?/1)
    end)
    |> MapSet.new()
  end

  defp resolve_flow_shortcut(data, %{flow_shortcuts_by_id: flow_shortcuts_by_id}) do
    resolve_flow_shortcut(data, flow_shortcuts_by_id)
  end

  defp resolve_flow_shortcut(data, flow_shortcuts_by_id) do
    data["flow_shortcut"] ||
      data["referenced_flow_shortcut"] ||
      flow_shortcuts_by_id[to_string(data["referenced_flow_id"])]
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp indent(0), do: ""
  defp indent(n), do: String.duplicate("    ", n)

  defp next_line_id(counter) do
    :counters.add(counter, 1, 1)
    n = :counters.get(counter, 1)
    "line_#{String.pad_leading(to_string(n), 4, "0")}"
  end

  defp build_yarn_condition(nil), do: nil
  defp build_yarn_condition(""), do: nil

  defp build_yarn_condition(condition) do
    parsed = Helpers.extract_condition(condition)

    case ExpressionTranspiler.transpile_condition(parsed, :yarn) do
      {:ok, expr, _} when expr != "" -> expr
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Metadata
  # ---------------------------------------------------------------------------

  defp build_metadata(project, sheets, variables, flows) do
    characters =
      Map.new(sheets, fn sheet ->
        {sheet.shortcut,
         %{
           "name" => sheet.name,
           "yarn_name" => sheet.name
         }}
      end)

    variable_mapping =
      Map.new(variables, fn var ->
        {var.full_ref, "$#{Helpers.shortcut_to_identifier(var.full_ref)}"}
      end)

    flow_mapping =
      Map.new(flows, fn flow ->
        {flow.shortcut || flow.name, Helpers.shortcut_to_identifier(flow.shortcut || flow.name || "flow_#{flow.id}")}
      end)

    required_functions = collect_required_functions(flows)

    metadata = %{
      "storyarn_yarn_metadata" => "1.0.0",
      "project" => project.name,
      "characters" => characters,
      "variable_mapping" => variable_mapping,
      "flow_mapping" => flow_mapping
    }

    if required_functions == [] do
      metadata
    else
      Map.put(metadata, "required_functions", required_functions)
    end
  end

  @custom_function_ops %{
    "contains" => "string_contains",
    "not_contains" => "string_contains",
    "starts_with" => "string_starts_with",
    "ends_with" => "string_ends_with"
  }

  defp collect_required_functions(flows) do
    flows
    |> Enum.flat_map(fn flow ->
      Enum.flat_map(flow.nodes || [], &extract_condition_operators/1)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_condition_operators(%{type: "condition", data: data}) when is_map(data) do
    condition = Helpers.extract_condition(data["condition"])
    extract_ops_from_condition(condition)
  end

  defp extract_condition_operators(%{type: "dialogue", data: data}) when is_map(data) do
    Enum.flat_map(data["responses"] || [], fn resp ->
      condition = Helpers.extract_condition(resp["condition"])
      extract_ops_from_condition(condition)
    end)
  end

  defp extract_condition_operators(_), do: []

  defp extract_ops_from_condition(%{"rules" => rules}) when is_list(rules) do
    rules
    |> Enum.map(& &1["operator"])
    |> Enum.filter(&Map.has_key?(@custom_function_ops, &1))
    |> Enum.map(&Map.fetch!(@custom_function_ops, &1))
  end

  defp extract_ops_from_condition(%{"blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, fn
      %{"rules" => rules} when is_list(rules) ->
        rules
        |> Enum.map(& &1["operator"])
        |> Enum.filter(&Map.has_key?(@custom_function_ops, &1))
        |> Enum.map(&Map.fetch!(@custom_function_ops, &1))

      %{"type" => "group", "blocks" => inner} when is_list(inner) ->
        extract_ops_from_condition(%{"blocks" => inner})

      _ ->
        []
    end)
  end

  defp extract_ops_from_condition(_), do: []
end
