defmodule Storyarn.Projects.Imports.Parsers.Yarn.Materialization do
  @moduledoc """
  Yarn-specific final rendering for a parser-v5 import plan.

  Source text is intentionally retained in durable plans until the target
  project's Sheet shortcuts and review decisions are known. This adapter owns
  that versioned metadata and removes it before rows are persisted.
  """

  alias Storyarn.Projects.Imports.ImportedVariableRewriter
  alias Storyarn.Projects.Imports.Parsers.Yarn.Expression
  alias Storyarn.Projects.Imports.Parsers.Yarn.Layout
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerClassifier

  @transient_node_data_keys ~w(
    import_yarn_inherited_speaker
    import_yarn_speaker
    import_yarn_literal_text
    import_yarn_literal_source_text
    import_yarn_source_text
  )

  @spec rewrite_node_data(map(), String.t(), %{optional(String.t()) => String.t()}) :: map()
  def rewrite_node_data(data, _type, renames) when renames == %{}, do: data

  def rewrite_node_data(data, "dialogue", renames) when is_map(data) do
    data
    |> rewrite_dialogue_text(renames)
    |> Map.update("responses", [], fn
      responses when is_list(responses) -> Enum.map(responses, &rewrite_response_interpolations(&1, renames))
      responses -> responses
    end)
  end

  def rewrite_node_data(data, _type, _renames), do: data

  @spec finalize_flow(map(), %{optional(String.t()) => String.t()}) :: map()
  def finalize_flow(%{"settings" => %{"import_source" => "yarn_spinner"}, "nodes" => nodes} = flow_data, shortcut_renames)
      when is_list(nodes) do
    layout_nodes =
      Enum.map(nodes, fn node ->
        data =
          node
          |> Map.get("data", %{})
          |> ImportedVariableRewriter.rewrite_node_data(node["type"], shortcut_renames)
          |> rewrite_node_data(node["type"], shortcut_renames)

        Map.put(node, "data", data)
      end)

    positions =
      layout_nodes
      |> Layout.assign_positions(
        flow_data["connections"] || [],
        flow_data["import_yarn_annotation_anchors"] || %{}
      )
      |> Map.new(&{&1["id"], {&1["position_x"], &1["position_y"]}})

    positioned_nodes =
      Enum.map(nodes, fn node ->
        case Map.fetch(positions, node["id"]) do
          {:ok, {x, y}} -> node |> Map.put("position_x", x) |> Map.put("position_y", y)
          :error -> node
        end
      end)

    Map.put(flow_data, "nodes", positioned_nodes)
  end

  def finalize_flow(flow_data, _shortcut_renames), do: flow_data

  @spec clean_node_data(map()) :: map()
  def clean_node_data(data) when is_map(data) do
    data
    |> Map.drop(@transient_node_data_keys)
    |> Map.update("responses", [], fn
      responses when is_list(responses) ->
        Enum.map(responses, fn
          response when is_map(response) -> Map.delete(response, "import_yarn_source_text")
          response -> response
        end)

      responses ->
        responses
    end)
  end

  defp rewrite_dialogue_text(%{"import_yarn_source_text" => source_text} = data, renames) when is_binary(source_text) do
    shortcut = Map.get(renames, "yarn", "yarn")

    data
    |> dialogue_source_for_rendering(source_text)
    |> Expression.interpolate(:dialogue, shortcut)
    |> then(&Map.put(data, "text", &1))
  end

  defp rewrite_dialogue_text(data, _renames), do: data

  defp dialogue_source_for_rendering(data, source_text) do
    case Map.get(data, "import_yarn_speaker") do
      speaker when is_binary(speaker) ->
        full_source = legacy_literal_source(data) || source_text

        if is_nil(Map.get(data, "speaker_sheet_id")),
          do: full_source,
          else: explicit_dialogue_body(full_source, source_text, speaker)

      _ordinary_or_inherited ->
        source_text
    end
  end

  defp legacy_literal_source(%{"import_yarn_literal_source_text" => source_text}) when is_binary(source_text),
    do: source_text

  defp legacy_literal_source(_data), do: nil

  defp explicit_dialogue_body(full_source, fallback_source, speaker) do
    case SpeakerClassifier.split(full_source) do
      {^speaker, body} -> body
      _legacy_body_only -> fallback_source
    end
  end

  defp rewrite_response_interpolations(%{"import_yarn_source_text" => source_text} = response, renames)
       when is_binary(source_text) do
    shortcut = Map.get(renames, "yarn", "yarn")
    Map.put(response, "text", Expression.interpolate(source_text, :response, shortcut))
  end

  defp rewrite_response_interpolations(response, _renames), do: response
end
