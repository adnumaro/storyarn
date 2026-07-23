defmodule Storyarn.AI.Context.Builders.Dialogue do
  @moduledoc false

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.Flows
  alias Storyarn.Sheets

  @default_dialogue_fields ~w(text stage_directions menu_text technical_id location)

  @spec build(map(), SubjectRef.t(), Policy.t()) :: {:ok, map()} | {:error, atom()}
  def build(project, %SubjectRef{} = subject_ref, %Policy{} = policy) do
    with {flow, node} <- Flows.get_context_node(project.id, subject_ref.subject_id),
         true <- node.type == "dialogue" || {:error, :context_subject_mismatch},
         {:ok, entities, excluded, warnings} <-
           dialogue_entities(project.id, flow, node, subject_ref, policy) do
      {:ok, %{entities: entities, excluded: excluded, warnings: warnings}}
    else
      nil -> {:error, :context_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dialogue_entities(project_id, flow, node, subject_ref, policy) do
    data = stringify_map(node.data || %{})
    dialogue_fields = Map.get(policy.fields, :dialogue, @default_dialogue_fields)
    selected_data = Map.take(data, dialogue_fields)

    with {:ok, node_entity} <-
           Entity.new(
             "flow_node",
             node.id,
             %{
               "type" => node.type,
               "data" => selected_data
             },
             required: true,
             priority: 1,
             revision: node.updated_at
           ),
         {:ok, flow_entity} <-
           Entity.new(
             "flow",
             flow.id,
             %{
               "name" => flow.name,
               "shortcut" => flow.shortcut,
               "description" => flow.description
             },
             priority: 3,
             revision: flow.updated_at
           ),
         {:ok, response_entities, response_excluded} <-
           response_entities(data["responses"], subject_ref.response_id, policy),
         {:ok, speaker_entities, speaker_excluded, speaker_warnings} <-
           speaker_entities(project_id, data["speaker_sheet_id"], policy) do
      excluded = speaker_excluded ++ response_excluded

      {:ok, [node_entity] ++ speaker_entities ++ [flow_entity] ++ response_entities, excluded,
       truncation_warnings(speaker_warnings, excluded)}
    end
  end

  defp response_entities(responses, selected_id, policy) when is_list(responses) do
    normalized =
      responses
      |> Enum.filter(&is_map/1)
      |> Enum.map(&stringify_map/1)
      |> Enum.sort_by(&Map.get(&1, "id", ""))

    with :ok <- selected_response_present(normalized, selected_id) do
      normalized = selected_first(normalized, selected_id)
      {allowed, overflow} = Enum.split(normalized, policy.max_fan_out)

      allowed
      |> Enum.reduce_while({:ok, []}, &reduce_response(&1, &2, selected_id))
      |> finalize_responses(overflow)
    end
  end

  defp response_entities(_responses, nil, _policy), do: {:ok, [], []}
  defp response_entities(_responses, _selected_id, _policy), do: {:error, :context_missing}

  defp selected_response_present(_responses, nil), do: :ok

  defp selected_response_present(responses, selected_id) do
    if Enum.any?(responses, &(&1["id"] == selected_id)),
      do: :ok,
      else: {:error, :context_missing}
  end

  defp reduce_response(response, {:ok, acc}, selected_id) do
    response_id = response["id"] || "response-" <> Integer.to_string(length(acc) + 1)
    required? = not is_nil(selected_id) and response_id == selected_id

    case Entity.new(
           "dialogue_response",
           response_id,
           Map.take(response, ~w(id text menu_text technical_id condition)),
           required: required?,
           priority: if(required?, do: 1, else: 4)
         ) do
      {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp finalize_responses({:ok, entities}, overflow) do
    {:ok, Enum.reverse(entities), Enum.map(overflow, &excluded_response/1)}
  end

  defp finalize_responses({:error, reason}, _overflow), do: {:error, reason}

  defp excluded_response(response) do
    %{
      "type" => "dialogue_response",
      "id" => response["id"] || "unknown",
      "reason" => "fan_out_limit"
    }
  end

  defp selected_first(responses, nil), do: responses

  defp selected_first(responses, selected_id) do
    {selected, rest} = Enum.split_with(responses, &(&1["id"] == selected_id))
    selected ++ rest
  end

  defp speaker_entities(_project_id, nil, _policy), do: {:ok, [], [], []}

  defp speaker_entities(project_id, raw_sheet_id, policy) do
    with {:ok, sheet_id} <- normalize_id(raw_sheet_id),
         sheet when not is_nil(sheet) <- Sheets.get_context_sheet(project_id, sheet_id),
         {:ok, sheet_entity} <-
           Entity.new(
             "sheet",
             sheet.id,
             %{
               "name" => sheet.name,
               "shortcut" => sheet.shortcut,
               "description" => sheet.description
             },
             required: true,
             priority: 2,
             revision: sheet.updated_at
           ),
         {:ok, block_entities} <- speaker_block_entities(project_id, sheet.id, policy) do
      {:ok, [sheet_entity | block_entities], [], []}
    else
      :error ->
        stale_speaker(raw_sheet_id)

      nil ->
        stale_speaker(raw_sheet_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp speaker_block_entities(project_id, sheet_id, policy) do
    labels = Map.get(policy.fields, :speaker_blocks, [])

    project_id
    |> Sheets.list_context_blocks_by_labels(sheet_id, labels, policy.max_fan_out)
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, acc} ->
      case Entity.new(
             "sheet_block",
             block.id,
             %{
               "type" => block.type,
               "label" => get_in(block.config, ["label"]),
               "value" => block.value
             },
             priority: 3,
             revision: block.updated_at
           ) do
        {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entities} -> {:ok, Enum.reverse(entities)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stale_speaker(raw_sheet_id) do
    {:ok, [], [%{"type" => "sheet", "id" => raw_sheet_id, "reason" => "stale_reference"}], ["stale_reference"]}
  end

  defp normalize_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _other -> :error
    end
  end

  defp normalize_id(_value), do: :error

  defp stringify_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp truncation_warnings(warnings, []), do: warnings
  defp truncation_warnings(warnings, _excluded), do: ["optional_context_truncated" | warnings]
end
