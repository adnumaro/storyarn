defmodule Storyarn.Exports.Serializers.GodotJSON do
  @moduledoc """
  Generic Godot JSON serializer.

  Produces JSON parseable by Godot's JSON class. No addons required.
  Variable names use underscores (GDScript-compatible).
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.{ExportOptions, ExpressionTranspiler}
  alias Storyarn.Exports.Serializers.Helpers

  @impl true
  def content_type, do: "application/json"

  @impl true
  def file_extension, do: "json"

  @impl true
  def format_label, do: "Godot (JSON)"

  @impl true
  def supported_sections, do: [:flows, :sheets, :scenes]

  @impl true
  def serialize(project_data, %ExportOptions{} = opts) do
    sheets = project_data.sheets || []
    flows = project_data.flows || []
    variables = Helpers.collect_variables(sheets)
    speaker_map = Helpers.build_speaker_map(sheets)

    result = %{
      "format" => "godot_dialogue",
      "version" => "1.0.0",
      "storyarn_version" => opts.version,
      "characters" => build_characters(sheets),
      "variables" => build_variables(variables),
      "flows" => build_flows(flows, speaker_map)
    }

    json_opts = if opts.pretty_print, do: [pretty: true], else: []
    {:ok, Jason.encode!(result, json_opts)}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Characters
  # ---------------------------------------------------------------------------

  defp build_characters(sheets) do
    Map.new(sheets, fn sheet ->
      properties =
        sheet.blocks
        |> Enum.reject(& &1.is_constant)
        |> Enum.filter(&(is_binary(&1.variable_name) and &1.variable_name != ""))
        |> Map.new(fn block ->
          {block.variable_name,
           %{
             "type" => to_string(Helpers.infer_variable_type(block)),
             "value" => Helpers.infer_default_value(block)
           }}
        end)

      {sheet.shortcut,
       %{
         "name" => sheet.name,
         "properties" => properties
       }}
    end)
  end

  # ---------------------------------------------------------------------------
  # Variables
  # ---------------------------------------------------------------------------

  defp build_variables(variables) do
    Map.new(variables, fn var ->
      godot_name = Helpers.shortcut_to_identifier(var.full_ref)

      {godot_name,
       %{
         "type" => to_string(var.type),
         "default" => var.default,
         "source" => var.full_ref
       }}
    end)
  end

  # ---------------------------------------------------------------------------
  # Flows
  # ---------------------------------------------------------------------------

  defp build_flows(flows, speaker_map) do
    Map.new(flows, fn flow ->
      conn_graph = Helpers.connection_graph(flow)
      entry = Helpers.find_entry_node(flow)

      nodes =
        Map.new(flow.nodes, fn node ->
          {to_string(node.id), build_node(node, conn_graph, speaker_map)}
        end)

      flow_data = %{
        "name" => flow.name,
        "start_node" => if(entry, do: to_string(entry.id), else: nil),
        "nodes" => nodes
      }

      {flow.shortcut || flow.name, flow_data}
    end)
  end

  defp build_node(node, conn_graph, speaker_map) do
    targets = Helpers.outgoing_targets(node.id, conn_graph)
    next_ids = Enum.map(targets, fn {target_id, _pin, _conn} -> to_string(target_id) end)
    base = %{"type" => node.type, "next" => next_ids}

    build_typed_node(node.type, node.data || %{}, base, speaker_map)
  end

  defp build_typed_node("dialogue", data, base, speaker_map) do
    resp_data =
      data
      |> Helpers.dialogue_responses()
      |> Enum.map(fn resp ->
        resp_condition =
          case Helpers.extract_condition(resp["condition"]) do
            nil -> nil
            cond -> transpile_or_nil(cond, :godot, :condition)
          end

        %{
          "id" => resp["id"],
          "text" => Helpers.strip_html(resp["text"] || ""),
          "next" => nil,
          "condition" => resp_condition
        }
      end)

    Map.merge(base, %{
      "character" => Helpers.speaker_shortcut(data, speaker_map),
      "text" => Helpers.dialogue_text(data),
      "stage_directions" => Helpers.strip_html(data["stage_directions"] || ""),
      "responses" => resp_data
    })
  end

  defp build_typed_node("condition", data, base, _speaker_map) do
    condition = Helpers.extract_condition(data["condition"])
    Map.merge(base, %{"condition" => transpile_or_nil(condition, :godot, :condition)})
  end

  defp build_typed_node("instruction", data, base, _speaker_map) do
    assignments = Helpers.extract_assignments(data)

    Map.merge(base, %{
      "code" => transpile_or_nil(assignments, :godot, :instruction),
      "assignments" => assignments
    })
  end

  defp build_typed_node("hub", data, base, _speaker_map) do
    Map.merge(base, %{"label" => data["label"] || ""})
  end

  defp build_typed_node("jump", data, base, _speaker_map) do
    Map.merge(base, %{"target" => data["hub_id"] || data["target_flow_shortcut"]})
  end

  defp build_typed_node("subflow", data, base, _speaker_map) do
    Map.merge(base, %{"flow_shortcut" => data["flow_shortcut"]})
  end

  defp build_typed_node("scene", data, base, _speaker_map) do
    Map.merge(base, %{"location" => data["location"] || data["slug_line"] || ""})
  end

  defp build_typed_node("exit", data, base, _speaker_map) do
    Map.merge(base, %{"technical_id" => data["technical_id"] || ""})
  end

  defp build_typed_node(_type, _data, base, _speaker_map), do: base

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp transpile_or_nil(nil, _engine, _type), do: nil
  defp transpile_or_nil([], _engine, _type), do: nil

  defp transpile_or_nil(data, engine, :condition) do
    case ExpressionTranspiler.transpile_condition(data, engine) do
      {:ok, expr, _} when expr != "" -> expr
      _ -> nil
    end
  end

  defp transpile_or_nil(data, engine, :instruction) do
    case ExpressionTranspiler.transpile_instruction(data, engine) do
      {:ok, expr, _} when expr != "" -> expr
      _ -> nil
    end
  end
end
