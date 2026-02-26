defmodule Storyarn.Exports.Serializers.UnityJSON do
  @moduledoc """
  Unity Dialogue System JSON serializer.

  Produces JSON compatible with Dialogue System for Unity by PixelCrushers.
  Sheets → Actors, Flows → Conversations with entries, Variables → global table.
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.{ExportOptions, ExpressionTranspiler}
  alias Storyarn.Exports.Serializers.Helpers

  @impl true
  def content_type, do: "application/json"

  @impl true
  def file_extension, do: "json"

  @impl true
  def format_label, do: "Unity Dialogue System (JSON)"

  @impl true
  def supported_sections, do: [:flows, :sheets]

  @impl true
  def serialize(project_data, %ExportOptions{} = opts) do
    sheets = project_data.sheets || []
    flows = project_data.flows || []
    variables = Helpers.collect_variables(sheets)
    speaker_map = Helpers.build_speaker_map(sheets)

    # Build actor ID mapping (sequential integers)
    actor_id_map = build_actor_id_map(sheets)

    result = %{
      "format" => "unity_dialogue_system",
      "version" => "1.0.0",
      "storyarn_version" => opts.version,
      "database" => %{
        "actors" => build_actors(sheets, actor_id_map),
        "conversations" => build_conversations(flows, actor_id_map, speaker_map),
        "variables" => build_variables(variables)
      }
    }

    json_opts = if opts.pretty_print, do: [pretty: true], else: []
    {:ok, Jason.encode!(result, json_opts)}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Actors
  # ---------------------------------------------------------------------------

  defp build_actor_id_map(sheets) do
    sheets
    |> Enum.with_index(1)
    |> Map.new(fn {sheet, idx} -> {to_string(sheet.id), idx} end)
  end

  defp build_actors(sheets, actor_id_map) do
    Enum.map(sheets, fn sheet ->
      fields =
        sheet.blocks
        |> Enum.reject(& &1.is_constant)
        |> Enum.filter(&(is_binary(&1.variable_name) and &1.variable_name != ""))
        |> Map.new(fn block ->
          {block.variable_name, Helpers.infer_default_value(block)}
        end)

      %{
        "id" => actor_id_map[to_string(sheet.id)],
        "name" => sheet.name,
        "shortcut" => sheet.shortcut,
        "fields" => fields
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  defp build_conversations(flows, actor_id_map, speaker_map) do
    flows
    |> Enum.with_index(1)
    |> Enum.map(fn {flow, conv_id} ->
      entries = build_entries(flow, actor_id_map, speaker_map)

      %{
        "id" => conv_id,
        "title" => flow.name,
        "shortcut" => flow.shortcut,
        "entries" => entries
      }
    end)
  end

  defp build_entries(flow, actor_id_map, speaker_map) do
    nodes = Helpers.node_index(flow)
    conn_graph = Helpers.connection_graph(flow)

    flow.nodes
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {node, entry_id} ->
      build_entry(node, entry_id, nodes, conn_graph, actor_id_map, speaker_map)
    end)
  end

  defp build_entry(node, entry_id, _nodes, conn_graph, actor_id_map, _speaker_map) do
    targets = Helpers.outgoing_targets(node.id, conn_graph)
    links_to = Enum.map(targets, fn {target_id, _pin, _conn} -> target_id end)

    base = %{
      "id" => entry_id,
      "storyarn_node_id" => node.id,
      "node_type" => node.type,
      "is_root" => node.type == "entry",
      "is_group" => node.type in ["hub", "entry"],
      "links_to" => links_to
    }

    build_typed_entry(node.type, node.data || %{}, base, entry_id, actor_id_map)
  end

  defp build_typed_entry("dialogue", data, base, entry_id, actor_id_map) do
    actor_id = resolve_actor_id(data, actor_id_map)
    condition = maybe_transpile_condition(data["condition"])

    entry =
      Map.merge(base, %{
        "actor_id" => actor_id,
        "dialogue_text" => Helpers.dialogue_text(data),
        "menu_text" => data["menu_text"] || "",
        "conditions" => condition,
        "user_script" => "",
        "stage_directions" => Helpers.strip_html(data["stage_directions"] || "")
      })

    response_entries = build_response_entries(data, entry_id)
    [entry | response_entries]
  end

  defp build_typed_entry("condition", data, base, _entry_id, _actor_id_map) do
    condition = Helpers.extract_condition(data["condition"])

    [
      Map.merge(base, %{
        "conditions" => transpile_or_empty(condition, :unity, :condition),
        "user_script" => ""
      })
    ]
  end

  defp build_typed_entry("instruction", data, base, _entry_id, _actor_id_map) do
    assignments = Helpers.extract_assignments(data)

    [
      Map.merge(base, %{
        "conditions" => "",
        "user_script" => transpile_or_empty(assignments, :unity, :instruction)
      })
    ]
  end

  defp build_typed_entry(_type, _data, base, _entry_id, _actor_id_map), do: [base]

  defp build_response_entries(data, entry_id) do
    data
    |> Helpers.dialogue_responses()
    |> Enum.with_index(1)
    |> Enum.map(fn {resp, resp_idx} ->
      resp_condition = maybe_transpile_condition(resp["condition"])

      resp_script =
        case resp["instruction_assignments"] do
          [_ | _] = assigns -> transpile_or_empty(assigns, :unity, :instruction)
          _ -> ""
        end

      %{
        "id" => entry_id * 1000 + resp_idx,
        "storyarn_response_id" => resp["id"],
        "node_type" => "response",
        "is_root" => false,
        "is_group" => false,
        "actor_id" => 0,
        "dialogue_text" => Helpers.strip_html(resp["text"] || ""),
        "menu_text" => Helpers.strip_html(resp["menu_text"] || resp["text"] || ""),
        "conditions" => resp_condition,
        "user_script" => resp_script,
        "links_to" => []
      }
    end)
  end

  defp maybe_transpile_condition(raw_condition) do
    case Helpers.extract_condition(raw_condition) do
      nil -> ""
      cond -> transpile_or_empty(cond, :unity, :condition)
    end
  end

  # ---------------------------------------------------------------------------
  # Variables
  # ---------------------------------------------------------------------------

  defp build_variables(variables) do
    Enum.map(variables, fn var ->
      %{
        "name" => var.full_ref,
        "type" => to_string(var.type),
        "initial_value" => var.default
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp resolve_actor_id(data, actor_id_map) do
    case data["speaker_sheet_id"] do
      nil -> 0
      "" -> 0
      id -> actor_id_map[to_string(id)] || 0
    end
  end

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
