defmodule Storyarn.Versioning.Builders.FlowSnapshotNormalizer do
  @moduledoc false

  alias Storyarn.Localization.RuntimeKey

  @response_field_prefix "response."
  @response_field_suffix ".text"
  @node_data_id_fields ~w(
    audio_asset_id location_sheet_id referenced_flow_id speaker_sheet_id target_id
  )
  @localization_id_fields ~w(source_id speaker_sheet_id vo_asset_id)

  @spec normalize(map()) :: map()
  def normalize(snapshot) when is_map(snapshot) do
    reserved_dialogue_ids = reserved_dialogue_ids(snapshot)

    {snapshot, _response_id_maps, _used_dialogue_ids} =
      normalize_with_response_id_maps(snapshot, MapSet.new(), reserved_dialogue_ids, %{})

    snapshot
  end

  def normalize(snapshot), do: snapshot

  @doc """
  Canonicalizes database IDs that may have been encoded as decimal strings.

  Portable/project recovery accepts this narrow legacy representation, but the
  materializers still validate and store one canonical integer identity. Values
  that are not exact positive decimal integers are left untouched so the strict
  snapshot validators can reject them with their normal error contract.
  """
  @spec normalize_entity_ids(map()) :: map()
  def normalize_entity_ids(snapshot) when is_map(snapshot) do
    snapshot
    |> normalize_known_ids(~w(original_id scene_id))
    |> update_existing("nodes", &normalize_node_entity_ids/1)
    |> update_existing("connections", &normalize_original_ids/1)
    |> update_existing("localization", &normalize_localization_entity_ids/1)
  end

  def normalize_entity_ids(snapshot), do: snapshot

  @spec normalize_project(map()) :: map()
  def normalize_project(snapshot) when is_map(snapshot) do
    snapshot = normalize_project_entity_ids(snapshot)

    case Map.fetch(snapshot, "flows") do
      {:ok, flows} when is_list(flows) ->
        reserved_dialogue_ids = reserved_project_dialogue_ids(flows)
        project_response_references = referenced_project_response_ids(snapshot)

        {flows, {project_response_ids, _used_dialogue_ids}} =
          Enum.map_reduce(flows, {%{}, MapSet.new()}, fn
            %{"snapshot" => flow_snapshot} = flow_entry, {project_response_ids, used_dialogue_ids}
            when is_map(flow_snapshot) ->
              {flow_snapshot, response_id_maps, used_dialogue_ids} =
                normalize_with_response_id_maps(
                  flow_snapshot,
                  used_dialogue_ids,
                  reserved_dialogue_ids,
                  project_response_references
                )

              project_response_ids =
                Map.merge(project_response_ids, response_ids_by_node(response_id_maps))

              {Map.put(flow_entry, "snapshot", flow_snapshot), {project_response_ids, used_dialogue_ids}}

            flow_entry, acc ->
              {flow_entry, acc}
          end)

        snapshot
        |> Map.put("flows", flows)
        |> normalize_existing_project_localization(project_response_ids)

      _missing_or_malformed_flows ->
        snapshot
    end
  end

  def normalize_project(snapshot), do: snapshot

  defp normalize_project_entity_ids(snapshot) do
    snapshot
    |> update_existing("flows", fn
      flows when is_list(flows) ->
        Enum.map(flows, fn
          %{"snapshot" => flow_snapshot} = flow_entry when is_map(flow_snapshot) ->
            Map.put(flow_entry, "snapshot", normalize_entity_ids(flow_snapshot))

          flow_entry ->
            flow_entry
        end)

      flows ->
        flows
    end)
    |> update_existing("localization", &normalize_project_localization_entity_ids/1)
  end

  defp normalize_node_entity_ids(nodes) when is_list(nodes) do
    Enum.map(nodes, fn
      %{} = node ->
        node
        |> normalize_known_ids(~w(original_id parent_id))
        |> update_existing("data", &normalize_known_ids(&1, @node_data_id_fields))
        |> update_existing("sequence_tracks", &normalize_sequence_resource_ids/1)
        |> update_existing("sequence_visual_layers", &normalize_sequence_resource_ids/1)

      node ->
        node
    end)
  end

  defp normalize_node_entity_ids(nodes), do: nodes

  defp normalize_sequence_resource_ids(resources) when is_list(resources) do
    Enum.map(resources, &normalize_known_ids(&1, ~w(original_id asset_id)))
  end

  defp normalize_sequence_resource_ids(resources), do: resources

  defp normalize_original_ids(entries) when is_list(entries) do
    Enum.map(entries, &normalize_known_ids(&1, ~w(original_id)))
  end

  defp normalize_original_ids(entries), do: entries

  defp normalize_localization_entity_ids(rows) when is_list(rows) do
    Enum.map(rows, &normalize_known_ids(&1, @localization_id_fields))
  end

  defp normalize_localization_entity_ids(rows), do: rows

  defp normalize_project_localization_entity_ids(%{} = localization) do
    update_existing(localization, "texts", &normalize_localization_entity_ids/1)
  end

  defp normalize_project_localization_entity_ids(localization), do: localization

  defp normalize_known_ids(%{} = value, fields) do
    Enum.reduce(fields, value, fn field, normalized ->
      update_existing(normalized, field, &canonical_positive_id/1)
    end)
  end

  defp normalize_known_ids(value, _fields), do: value

  defp canonical_positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _invalid -> value
    end
  end

  defp canonical_positive_id(value), do: value

  defp normalize_with_response_id_maps(snapshot, used_dialogue_ids, reserved_dialogue_ids, project_response_references) do
    case Map.fetch(snapshot, "nodes") do
      {:ok, nodes} when is_list(nodes) ->
        response_references =
          snapshot
          |> referenced_flow_response_ids()
          |> merge_response_references(project_response_references)

        {normalized_nodes, response_id_maps, used_dialogue_ids} =
          nodes
          |> Enum.with_index()
          |> Enum.reduce(
            {[], %{}, used_dialogue_ids},
            &normalize_node(&1, &2, reserved_dialogue_ids, response_references)
          )

        snapshot =
          snapshot
          |> Map.put("nodes", Enum.reverse(normalized_nodes))
          |> update_existing("connections", &normalize_connections(&1, response_id_maps))
          |> update_existing("localization", &normalize_localization(&1, response_id_maps))

        {snapshot, response_id_maps, used_dialogue_ids}

      _missing_or_malformed_nodes ->
        {snapshot, %{}, used_dialogue_ids}
    end
  end

  defp normalize_node(
         {%{"type" => "dialogue"} = node, index},
         {nodes, response_id_maps, used_dialogue_ids},
         reserved_dialogue_ids,
         response_references
       ) do
    data = map_or_empty(node["data"])
    node_seed_ref = node_seed_ref(node, index)

    {localization_id, used_dialogue_ids} =
      unique_runtime_id(
        data["localization_id"],
        "dialogue",
        {:dialogue, node_seed_ref},
        used_dialogue_ids,
        reserved_dialogue_ids,
        &RuntimeKey.valid_dialogue_id?/1
      )

    reserved_response_ids = reserved_response_ids_for_node(response_references, node, index)

    {responses, response_id_map} =
      normalize_responses(data["responses"], node_seed_ref, reserved_response_ids)

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

  defp normalize_node(
         {node, _index},
         {nodes, response_id_maps, used_dialogue_ids},
         _reserved_dialogue_ids,
         _response_references
       ) do
    {[node | nodes], response_id_maps, used_dialogue_ids}
  end

  defp normalize_responses(responses, node_ref, referenced_response_ids) when is_list(responses) do
    reserved_response_ids =
      responses
      |> reserved_response_ids()
      |> MapSet.union(referenced_response_ids)

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
              reserved_response_ids,
              &RuntimeKey.valid_response_id?/1
            )

          {[Map.put(response, "id", new_id) | normalized], [{old_id, new_id} | pairs], used_ids}

        {response, _index}, {normalized, pairs, used_ids} ->
          {[response | normalized], pairs, used_ids}
      end)

    {Enum.reverse(responses), build_response_id_map(pairs)}
  end

  defp normalize_responses(responses, _node_ref, _referenced_response_ids), do: {responses, %{}}

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
    Enum.map(connections, fn
      %{} = connection ->
        response_ids = get_in(response_id_maps, [connection["source_node_index"], :ids]) || %{}
        update_existing(connection, "source_pin", &normalize_response_pin(&1, response_ids))

      connection ->
        connection
    end)
  end

  defp normalize_connections(connections, _response_id_maps), do: connections

  defp normalize_response_pin(pin, response_ids) when is_binary(pin) do
    case Map.fetch(response_ids, pin) do
      {:ok, new_id} ->
        new_id

      :error ->
        normalize_prefixed_response_pin(pin, response_ids)
    end
  end

  defp normalize_response_pin(pin, _response_ids), do: pin

  defp normalize_prefixed_response_pin("resp_" <> old_id = pin, response_ids) do
    case Map.fetch(response_ids, old_id) do
      {:ok, new_id} -> "resp_#{new_id}"
      :error -> pin
    end
  end

  defp normalize_prefixed_response_pin(pin, _response_ids), do: pin

  defp normalize_localization(localization, response_id_maps) when is_list(localization) do
    normalize_localization_rows(localization, response_ids_by_node(response_id_maps))
  end

  defp normalize_localization(localization, _response_id_maps), do: localization

  defp normalize_project_localization(%{} = localization, response_ids_by_node) do
    update_existing(localization, "texts", &normalize_localization_rows(&1, response_ids_by_node))
  end

  defp normalize_project_localization(localization, _response_ids_by_node), do: localization

  defp normalize_localization_rows(localization, response_ids_by_node) when is_list(localization) do
    Enum.map(localization, &normalize_localization_row(&1, response_ids_by_node))
  end

  defp normalize_localization_rows(localization, _response_ids_by_node), do: localization

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

  defp unique_runtime_id(current_id, prefix, seed, used_ids, reserved_ids, validator) do
    candidate =
      if validator.(current_id) and not MapSet.member?(used_ids, current_id) do
        current_id
      else
        initial_candidate = sanitize_runtime_id(current_id) || legacy_runtime_id(prefix, seed, 0)
        blocked_ids = MapSet.union(used_ids, reserved_ids)

        unique_candidate(initial_candidate, prefix, seed, blocked_ids, validator, 0)
      end

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

  defp reserved_project_dialogue_ids(flows) do
    Enum.reduce(flows, MapSet.new(), fn
      %{"snapshot" => snapshot}, reserved_ids when is_map(snapshot) ->
        MapSet.union(reserved_ids, reserved_dialogue_ids(snapshot))

      _flow_entry, reserved_ids ->
        reserved_ids
    end)
  end

  defp reserved_dialogue_ids(%{"nodes" => nodes}) when is_list(nodes) do
    Enum.reduce(nodes, MapSet.new(), fn
      %{"type" => "dialogue", "data" => %{"localization_id" => localization_id}}, reserved_ids ->
        maybe_reserve_id(reserved_ids, localization_id, &RuntimeKey.valid_dialogue_id?/1)

      _node, reserved_ids ->
        reserved_ids
    end)
  end

  defp reserved_dialogue_ids(_snapshot), do: MapSet.new()

  defp reserved_response_ids(responses) do
    Enum.reduce(responses, MapSet.new(), fn
      %{"id" => response_id}, reserved_ids ->
        maybe_reserve_id(reserved_ids, response_id, &RuntimeKey.valid_response_id?/1)

      _response, reserved_ids ->
        reserved_ids
    end)
  end

  defp referenced_flow_response_ids(snapshot) do
    %{}
    |> reserve_connection_response_ids(Map.get(snapshot, "connections"))
    |> reserve_localization_response_ids(Map.get(snapshot, "localization"))
  end

  defp referenced_project_response_ids(%{"localization" => %{"texts" => texts}}) do
    reserve_localization_response_ids(%{}, texts)
  end

  defp referenced_project_response_ids(_snapshot), do: %{}

  defp reserve_connection_response_ids(response_references, connections) when is_list(connections) do
    Enum.reduce(connections, response_references, fn
      %{"source_node_index" => source_node_index, "source_pin" => source_pin}, response_references ->
        Enum.reduce(response_ids_from_pin(source_pin), response_references, fn response_id, acc ->
          reserve_response_reference(acc, {:node_index, source_node_index}, response_id)
        end)

      _connection, response_references ->
        response_references
    end)
  end

  defp reserve_connection_response_ids(response_references, _connections), do: response_references

  defp reserve_localization_response_ids(response_references, localization) when is_list(localization) do
    Enum.reduce(localization, response_references, fn
      %{
        "source_type" => "flow_node",
        "source_id" => source_id,
        "source_field" => source_field
      },
      response_references
      when not is_nil(source_id) ->
        case response_id_from_field(source_field) do
          {:ok, response_id} ->
            reserve_response_reference(response_references, {:original_id, source_id}, response_id)

          :error ->
            response_references
        end

      _localization_row, response_references ->
        response_references
    end)
  end

  defp reserve_localization_response_ids(response_references, _localization), do: response_references

  defp response_ids_from_pin("resp_" <> response_id = source_pin), do: [source_pin, response_id]
  defp response_ids_from_pin(source_pin) when is_binary(source_pin), do: [source_pin]
  defp response_ids_from_pin(_source_pin), do: []

  defp reserve_response_reference(response_references, node_ref, response_id) do
    if RuntimeKey.valid_response_id?(response_id) do
      Map.update(
        response_references,
        node_ref,
        MapSet.new([response_id]),
        &MapSet.put(&1, response_id)
      )
    else
      response_references
    end
  end

  defp merge_response_references(left, right) do
    Map.merge(left, right, fn _node_ref, left_ids, right_ids ->
      MapSet.union(left_ids, right_ids)
    end)
  end

  defp reserved_response_ids_for_node(response_references, node, index) do
    referenced_by_index = Map.get(response_references, {:node_index, index}, MapSet.new())

    case Map.fetch(node, "original_id") do
      {:ok, original_id} when not is_nil(original_id) ->
        referenced_by_original_id =
          Map.get(response_references, {:original_id, original_id}, MapSet.new())

        MapSet.union(referenced_by_index, referenced_by_original_id)

      _missing_or_nil ->
        referenced_by_index
    end
  end

  defp maybe_reserve_id(reserved_ids, id, validator) do
    if validator.(id), do: MapSet.put(reserved_ids, id), else: reserved_ids
  end

  defp node_seed_ref(node, index) do
    case Map.fetch(node, "original_id") do
      {:ok, original_id} when not is_nil(original_id) -> original_id
      _missing_or_nil -> index
    end
  end

  defp normalize_existing_project_localization(snapshot, response_ids_by_node) do
    update_existing(
      snapshot,
      "localization",
      &normalize_project_localization(&1, response_ids_by_node)
    )
  end

  defp update_existing(map, key, function) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, function.(value))
      :error -> map
    end
  end

  defp map_or_empty(data) when is_map(data), do: data
  defp map_or_empty(_data), do: %{}
end
