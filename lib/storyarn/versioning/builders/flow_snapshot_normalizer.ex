defmodule Storyarn.Versioning.Builders.FlowSnapshotNormalizer do
  @moduledoc false

  alias Storyarn.Localization.RuntimeKey

  @response_field_prefix "response."
  @response_field_suffix ".text"

  @spec normalize(map()) :: map()
  def normalize(snapshot) when is_map(snapshot) do
    {snapshot, _response_id_maps} = normalize_with_response_id_maps(snapshot)
    snapshot
  end

  def normalize(snapshot), do: snapshot

  @spec normalize_project(map()) :: map()
  def normalize_project(snapshot) when is_map(snapshot) do
    {flows, project_response_ids} =
      snapshot
      |> Map.get("flows", [])
      |> Enum.map_reduce(%{}, fn flow_entry, project_response_ids ->
        {flow_snapshot, response_id_maps} =
          flow_entry
          |> Map.get("snapshot", %{})
          |> normalize_with_response_id_maps()

        project_response_ids =
          Map.merge(project_response_ids, response_ids_by_node(response_id_maps))

        {Map.put(flow_entry, "snapshot", flow_snapshot), project_response_ids}
      end)

    snapshot
    |> Map.put("flows", flows)
    |> Map.update("localization", %{}, &normalize_project_localization(&1, project_response_ids))
  end

  def normalize_project(snapshot), do: snapshot

  defp normalize_with_response_id_maps(snapshot) do
    nodes = Map.get(snapshot, "nodes", [])

    {normalized_nodes, response_id_maps, _used_dialogue_ids} =
      nodes
      |> Enum.with_index()
      |> Enum.reduce({[], %{}, MapSet.new()}, &normalize_node/2)

    snapshot =
      snapshot
      |> Map.put("nodes", Enum.reverse(normalized_nodes))
      |> Map.update("connections", [], &normalize_connections(&1, response_id_maps))
      |> Map.update("localization", [], &normalize_localization(&1, response_id_maps))

    {snapshot, response_id_maps}
  end

  defp normalize_node({%{"type" => "dialogue"} = node, index}, {nodes, response_id_maps, used_dialogue_ids}) do
    data = map_or_empty(node["data"])
    node_ref = node["original_id"] || index

    {localization_id, used_dialogue_ids} =
      unique_runtime_id(
        data["localization_id"],
        "dialogue",
        {:dialogue, node_ref, index},
        used_dialogue_ids,
        &RuntimeKey.valid_dialogue_id?/1
      )

    {responses, response_id_map} = normalize_responses(data["responses"], node_ref)

    data =
      data
      |> Map.put("localization_id", localization_id)
      |> maybe_put_responses(responses)

    response_id_maps =
      if map_size(response_id_map) == 0 do
        response_id_maps
      else
        Map.put(response_id_maps, index, %{node_ref: node["original_id"], ids: response_id_map})
      end

    {[Map.put(node, "data", data) | nodes], response_id_maps, used_dialogue_ids}
  end

  defp normalize_node({node, _index}, {nodes, response_id_maps, used_dialogue_ids}) do
    {[node | nodes], response_id_maps, used_dialogue_ids}
  end

  defp normalize_responses(responses, node_ref) when is_list(responses) do
    {responses, pairs, _used_ids} =
      responses
      |> Enum.with_index()
      |> Enum.reduce({[], [], MapSet.new()}, fn
        {%{} = response, index}, {normalized, pairs, used_ids} ->
          old_id = response["id"]

          {new_id, used_ids} =
            unique_runtime_id(
              old_id,
              "response",
              {:response, node_ref, index},
              used_ids,
              &RuntimeKey.valid_response_id?/1
            )

          {[Map.put(response, "id", new_id) | normalized], [{old_id, new_id} | pairs], used_ids}

        {response, _index}, {normalized, pairs, used_ids} ->
          {[response | normalized], pairs, used_ids}
      end)

    {Enum.reverse(responses), build_response_id_map(pairs)}
  end

  defp normalize_responses(responses, _node_ref), do: {responses, %{}}

  defp build_response_id_map(pairs) do
    pairs
    |> Enum.reject(fn {old_id, _new_id} -> not is_binary(old_id) or old_id == "" end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(%{}, fn {old_id, new_ids}, remaps ->
      if old_id in new_ids do
        remaps
      else
        Map.put(remaps, old_id, List.last(new_ids))
      end
    end)
  end

  defp normalize_connections(connections, response_id_maps) when is_list(connections) do
    Enum.map(connections, fn connection ->
      response_ids = get_in(response_id_maps, [connection["source_node_index"], :ids]) || %{}
      Map.update(connection, "source_pin", nil, &normalize_response_pin(&1, response_ids))
    end)
  end

  defp normalize_connections(connections, _response_id_maps), do: connections

  defp normalize_response_pin("resp_" <> old_id = pin, response_ids) do
    case Map.fetch(response_ids, old_id) do
      {:ok, new_id} -> "resp_#{new_id}"
      :error -> pin
    end
  end

  defp normalize_response_pin(pin, response_ids) when is_binary(pin), do: Map.get(response_ids, pin, pin)
  defp normalize_response_pin(pin, _response_ids), do: pin

  defp normalize_localization(localization, response_id_maps) when is_list(localization) do
    normalize_localization_rows(localization, response_ids_by_node(response_id_maps))
  end

  defp normalize_localization(localization, _response_id_maps), do: localization

  defp normalize_project_localization(%{} = localization, response_ids_by_node) do
    Map.update(localization, "texts", [], &normalize_localization_rows(&1, response_ids_by_node))
  end

  defp normalize_project_localization(localization, _response_ids_by_node), do: localization

  defp normalize_localization_rows(localization, response_ids_by_node) do
    Enum.map(localization, &normalize_localization_row(&1, response_ids_by_node))
  end

  defp response_ids_by_node(response_id_maps) do
    response_id_maps
    |> Map.values()
    |> Enum.reduce(%{}, fn
      %{node_ref: nil}, acc -> acc
      %{node_ref: node_ref, ids: ids}, acc -> Map.put(acc, node_ref, ids)
    end)
  end

  defp normalize_localization_row(
         %{"source_type" => "flow_node", "source_id" => source_id, "source_field" => source_field} = row,
         response_ids_by_node
       ) do
    with response_ids when is_map(response_ids) <- Map.get(response_ids_by_node, source_id),
         {:ok, old_id} <- response_id_from_field(source_field),
         new_id when is_binary(new_id) <- Map.get(response_ids, old_id) do
      Map.put(row, "source_field", "#{@response_field_prefix}#{new_id}#{@response_field_suffix}")
    else
      _ -> row
    end
  end

  defp normalize_localization_row(row, _response_ids_by_node), do: row

  defp response_id_from_field(field) when is_binary(field) do
    if String.starts_with?(field, @response_field_prefix) and String.ends_with?(field, @response_field_suffix) do
      size = byte_size(field) - byte_size(@response_field_prefix) - byte_size(@response_field_suffix)

      if size > 0 do
        {:ok, binary_part(field, byte_size(@response_field_prefix), size)}
      else
        :error
      end
    else
      :error
    end
  end

  defp response_id_from_field(_field), do: :error

  defp unique_runtime_id(current_id, prefix, seed, used_ids, validator) do
    candidate =
      cond do
        validator.(current_id) -> current_id
        sanitized = sanitize_runtime_id(current_id) -> sanitized
        true -> legacy_runtime_id(prefix, seed, 0)
      end

    candidate = unique_candidate(candidate, prefix, seed, used_ids, validator, 0)
    {candidate, MapSet.put(used_ids, candidate)}
  end

  defp unique_candidate(candidate, prefix, seed, used_ids, validator, attempt) do
    if validator.(candidate) and not MapSet.member?(used_ids, candidate) do
      candidate
    else
      unique_candidate(
        legacy_runtime_id(prefix, seed, attempt + 1),
        prefix,
        seed,
        used_ids,
        validator,
        attempt + 1
      )
    end
  end

  defp sanitize_runtime_id(value) when is_binary(value) and value != "" do
    candidate =
      value
      |> String.replace(~r/[^A-Za-z0-9_-]/u, "_")
      |> String.slice(0, 100)

    if candidate == "", do: nil, else: candidate
  end

  defp sanitize_runtime_id(_value), do: nil

  defp legacy_runtime_id(prefix, seed, attempt) do
    suffix =
      {seed, attempt}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)

    "#{prefix}_legacy_#{suffix}"
  end

  defp maybe_put_responses(data, responses) when is_list(responses), do: Map.put(data, "responses", responses)
  defp maybe_put_responses(data, _responses), do: data

  defp map_or_empty(data) when is_map(data), do: data
  defp map_or_empty(_data), do: %{}
end
