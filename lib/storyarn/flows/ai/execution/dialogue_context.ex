defmodule Storyarn.Flows.AI.DialogueContext do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.AI.ContextContract
  alias Storyarn.Flows.AI.Projections.BlockRecord
  alias Storyarn.Flows.AI.Projections.SheetRecord
  alias Storyarn.Flows.ContextQueries
  alias Storyarn.Repo

  @default_dialogue_fields ~w(text stage_directions menu_text technical_id location)

  @spec build(map(), map(), map(), function()) :: {:ok, map()} | {:error, atom()}
  def build(project, subject_ref, policy, entity_builder) do
    with {flow, node} <- ContextQueries.get_node(project.id, subject_ref.subject_id),
         true <- node.type == "dialogue" || {:error, :context_subject_mismatch},
         {:ok, entities, excluded, warnings} <-
           dialogue_entities(project.id, flow, node, subject_ref, policy, entity_builder) do
      {:ok, %{entities: entities, excluded: excluded, warnings: warnings}}
    else
      nil -> {:error, :context_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dialogue_entities(project_id, flow, node, subject_ref, policy, entity_builder) do
    data = stringify_map(node.data || %{})
    dialogue_fields = Map.get(policy.fields, :dialogue, @default_dialogue_fields)
    selected_data = Map.take(data, dialogue_fields)

    with {:ok, node_entity} <-
           entity_builder.(
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
           entity_builder.(
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
           response_entities(data["responses"], ContextContract.response_id(subject_ref), policy, entity_builder),
         {:ok, speaker_entities, speaker_excluded, speaker_warnings} <-
           speaker_entities(project_id, data["speaker_sheet_id"], policy, entity_builder) do
      excluded = speaker_excluded ++ response_excluded

      {:ok, [node_entity] ++ speaker_entities ++ [flow_entity] ++ response_entities, excluded,
       truncation_warnings(speaker_warnings, excluded)}
    end
  end

  defp response_entities(responses, selected_id, policy, entity_builder) when is_list(responses) do
    normalized =
      responses
      |> Enum.filter(&is_map/1)
      |> Enum.map(&stringify_map/1)
      |> Enum.sort_by(&Map.get(&1, "id", ""))

    with :ok <- selected_response_present(normalized, selected_id) do
      normalized = selected_first(normalized, selected_id)
      {allowed, overflow} = Enum.split(normalized, policy.max_fan_out)
      {detailed_overflow, summarized_overflow} = Enum.split(overflow, policy.max_entities)

      allowed
      |> Enum.reduce_while({:ok, []}, &reduce_response(&1, &2, selected_id, entity_builder))
      |> finalize_responses(detailed_overflow, length(summarized_overflow))
    end
  end

  defp response_entities(_responses, nil, _policy, _entity_builder), do: {:ok, [], []}

  defp response_entities(_responses, _selected_id, _policy, _entity_builder), do: {:error, :context_missing}

  defp selected_response_present(_responses, nil), do: :ok

  defp selected_response_present(responses, selected_id) do
    if Enum.any?(responses, &(&1["id"] == selected_id)),
      do: :ok,
      else: {:error, :context_missing}
  end

  defp reduce_response(response, {:ok, acc}, selected_id, entity_builder) do
    response_id = response["id"] || "response-" <> Integer.to_string(length(acc) + 1)
    required? = not is_nil(selected_id) and response_id == selected_id

    case entity_builder.(
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

  defp finalize_responses({:ok, entities}, overflow, omitted_count) do
    excluded =
      overflow
      |> Enum.map(&excluded_response/1)
      |> maybe_add_response_overflow(omitted_count)

    {:ok, Enum.reverse(entities), excluded}
  end

  defp finalize_responses({:error, reason}, _overflow, _omitted_count), do: {:error, reason}

  defp excluded_response(response) do
    %{
      "type" => "dialogue_response",
      "id" => response["id"] || "unknown",
      "reason" => "fan_out_limit"
    }
  end

  defp maybe_add_response_overflow(excluded, omitted_count) when omitted_count > 0 do
    [
      %{
        "type" => "dialogue_response_overflow",
        "id" => "responses",
        "reason" => "fan_out_limit",
        "omitted_count" => omitted_count
      }
      | excluded
    ]
  end

  defp maybe_add_response_overflow(excluded, _omitted_count), do: excluded

  defp selected_first(responses, nil), do: responses

  defp selected_first(responses, selected_id) do
    {selected, rest} = Enum.split_with(responses, &(&1["id"] == selected_id))
    selected ++ rest
  end

  defp speaker_entities(_project_id, nil, _policy, _entity_builder), do: {:ok, [], [], []}

  defp speaker_entities(project_id, raw_sheet_id, policy, entity_builder) do
    with {:ok, sheet_id} <- normalize_id(raw_sheet_id),
         sheet when not is_nil(sheet) <- get_sheet(project_id, sheet_id),
         {:ok, sheet_entity} <-
           entity_builder.(
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
         {:ok, block_entities, block_excluded} <-
           speaker_block_entities(project_id, sheet.id, policy, entity_builder) do
      {:ok, [sheet_entity | block_entities], block_excluded, []}
    else
      :error ->
        stale_speaker(raw_sheet_id)

      nil ->
        stale_speaker(raw_sheet_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp speaker_block_entities(project_id, sheet_id, policy, entity_builder) do
    labels = Map.get(policy.fields, :speaker_blocks, [])
    detail_limit = policy.max_fan_out + policy.max_entities

    blocks = list_blocks_by_labels(project_id, sheet_id, labels, detail_limit)
    total_count = count_blocks_by_labels(project_id, sheet_id, labels)
    {included, overflow} = Enum.split(blocks, policy.max_fan_out)

    excluded =
      overflow
      |> Enum.map(&excluded_speaker_block/1)
      |> maybe_add_speaker_overflow(total_count - length(blocks), sheet_id)

    included
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, acc} ->
      case entity_builder.(
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
      {:ok, entities} -> {:ok, Enum.reverse(entities), excluded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp excluded_speaker_block(block) do
    %{
      "type" => "sheet_block",
      "id" => block.id,
      "reason" => "fan_out_limit"
    }
  end

  defp maybe_add_speaker_overflow(excluded, remaining, sheet_id) when remaining > 0 do
    [
      %{
        "type" => "sheet_block_overflow",
        "id" => "sheet-#{sheet_id}",
        "reason" => "fan_out_limit",
        "omitted_count" => remaining
      }
      | excluded
    ]
  end

  defp maybe_add_speaker_overflow(excluded, _remaining, _sheet_id), do: excluded

  defp get_sheet(project_id, sheet_id) do
    Repo.one(
      from(sheet in SheetRecord,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            is_nil(sheet.deleted_at)
      )
    )
  end

  defp list_blocks_by_labels(_project_id, _sheet_id, [], _limit), do: []

  defp list_blocks_by_labels(project_id, sheet_id, labels, limit) do
    Repo.all(
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            fragment("?->>'label' = ANY(?)", block.config, ^labels) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
        order_by: [asc: block.position, asc: block.id],
        limit: ^limit
      )
    )
  end

  defp count_blocks_by_labels(_project_id, _sheet_id, []), do: 0

  defp count_blocks_by_labels(project_id, sheet_id, labels) do
    Repo.aggregate(
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            fragment("?->>'label' = ANY(?)", block.config, ^labels) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at)
      ),
      :count,
      :id
    )
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
