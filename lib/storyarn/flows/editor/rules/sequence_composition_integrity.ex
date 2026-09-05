defmodule Storyarn.Flows.SequenceCompositionIntegrity do
  @moduledoc false

  @composition_owner_types ~w(sequence dialogue)
  @track_fields ~w(position asset_id start_time end_time volume)
  @visual_layer_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)

  @doc false
  @spec validate_nodes([map()]) :: :ok | {:error, term()}
  def validate_nodes(nodes) when is_list(nodes) do
    nodes_by_id = Map.new(nodes, &{&1["original_id"], &1})

    with :ok <- validate_node_contracts(nodes) do
      nodes
      |> Enum.filter(&(&1["type"] in @composition_owner_types))
      |> Enum.map(& &1["original_id"])
      |> validate_owner_ids(nodes_by_id)
    end
  end

  @doc false
  @spec validate_affected([map()], integer()) :: :ok | {:error, term()}
  def validate_affected(nodes, changed_owner_id) when is_list(nodes) and is_integer(changed_owner_id) do
    nodes_by_id = Map.new(nodes, &{&1["original_id"], &1})

    with :ok <- validate_node_contracts(nodes) do
      nodes
      |> Enum.filter(fn node ->
        node["type"] in @composition_owner_types and
          depends_on?(node["original_id"], changed_owner_id, nodes_by_id, MapSet.new())
      end)
      |> Enum.map(& &1["original_id"])
      |> validate_owner_ids(nodes_by_id)
    end
  end

  defp validate_node_contracts(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_node_contract(node) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_node_contract(%{"type" => "sequence"}), do: :ok

  defp validate_node_contract(%{"type" => "dialogue"} = node) do
    if is_nil(node["sequence_config"]),
      do: :ok,
      else: invalid_composition_payload(node, "sequence_config")
  end

  defp validate_node_contract(node) do
    invalid_field =
      Enum.find(
        [
          {"composition_source_original_id", node["composition_source_original_id"], nil},
          {"sequence_config", node["sequence_config"], nil},
          {"sequence_tracks", node["sequence_tracks"], []},
          {"sequence_visual_layers", node["sequence_visual_layers"], []}
        ],
        fn {_field, value, empty_value} -> value not in [nil, empty_value] end
      )

    case invalid_field do
      nil -> :ok
      {field, _value, _empty_value} -> invalid_composition_payload(node, field)
    end
  end

  defp invalid_composition_payload(node, field) do
    {:error, {:invalid_sequence_composition_payload, node["original_id"], field}}
  end

  defp validate_owner_ids(owner_ids, nodes_by_id) do
    Enum.reduce_while(owner_ids, :ok, fn owner_id, :ok ->
      case validate_owner(owner_id, nodes_by_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_owner(owner_id, nodes_by_id) do
    with {:ok, chain} <- composition_chain(owner_id, nodes_by_id, MapSet.new(), false),
         {:ok, _layers, _tracks} <-
           Enum.reduce_while(chain, {:ok, %{}, %{}}, &validate_composition_node/2) do
      :ok
    end
  end

  defp validate_composition_node(node, {:ok, layers, tracks}) do
    with {:ok, layers} <- apply_visual_layers(node, layers),
         {:ok, tracks} <- apply_tracks(node, tracks) do
      {:cont, {:ok, layers, tracks}}
    else
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp composition_chain(node_id, nodes_by_id, visited, source?) do
    if MapSet.member?(visited, node_id) do
      {:error, {:invalid_sequence_composition_chain, node_id}}
    else
      nodes_by_id
      |> Map.get(node_id)
      |> continue_composition_chain(node_id, nodes_by_id, visited, source?)
    end
  end

  defp continue_composition_chain(%{"type" => type} = node, node_id, nodes_by_id, visited, source?)
       when type in @composition_owner_types do
    if source? and not is_nil(node["deleted_at"]) do
      {:error, {:invalid_sequence_composition_chain, node_id}}
    else
      append_composition_source_chain(
        node,
        node_id,
        nodes_by_id,
        visited,
        node["composition_source_original_id"]
      )
    end
  end

  defp continue_composition_chain(_missing_or_invalid, node_id, _nodes_by_id, _visited, _source?),
    do: {:error, {:invalid_sequence_composition_chain, node_id}}

  defp append_composition_source_chain(node, _node_id, _nodes_by_id, _visited, nil), do: {:ok, [node]}

  defp append_composition_source_chain(node, node_id, nodes_by_id, visited, source_id) do
    with {:ok, source_chain} <-
           composition_chain(
             source_id,
             nodes_by_id,
             MapSet.put(visited, node_id),
             true
           ) do
      {:ok, source_chain ++ [node]}
    end
  end

  defp depends_on?(node_id, changed_owner_id, _nodes_by_id, _visited) when node_id == changed_owner_id, do: true

  defp depends_on?(node_id, changed_owner_id, nodes_by_id, visited) do
    if MapSet.member?(visited, node_id) do
      false
    else
      case get_in(nodes_by_id, [node_id, "composition_source_original_id"]) do
        source_id when is_integer(source_id) ->
          depends_on?(
            source_id,
            changed_owner_id,
            nodes_by_id,
            MapSet.put(visited, node_id)
          )

        _no_source ->
          false
      end
    end
  end

  defp apply_visual_layers(node, inherited) do
    apply_rows(
      node["sequence_visual_layers"] || [],
      inherited,
      node["original_id"],
      :sequence_visual_layer,
      &validate_visual_layer/2
    )
  end

  defp apply_tracks(node, inherited) do
    apply_rows(
      node["sequence_tracks"] || [],
      inherited,
      node["original_id"],
      :sequence_track,
      &validate_track/2
    )
  end

  defp apply_rows(rows, inherited, owner_id, kind, validator) do
    Enum.reduce_while(rows, {:ok, inherited}, fn row, {:ok, state} ->
      key = resource_key(row, kind)

      case validator.(row, Map.get(state, key)) do
        :ok -> {:cont, {:ok, Map.put(state, key, resource_state(row))}}
        {:error, reason} -> {:halt, invalid_resource(kind, owner_id, key, reason)}
      end
    end)
  end

  defp validate_visual_layer(row, nil) do
    cond do
      row["removed"] -> {:error, :missing_inherited_identity}
      complete_mask?(row["overridden_fields"], @visual_layer_fields) -> :ok
      true -> {:error, :incomplete_local_definition}
    end
  end

  defp validate_visual_layer(row, :removed) do
    if not row["removed"] and
         not complete_mask?(row["overridden_fields"], @visual_layer_fields),
       do: {:error, :incomplete_tombstone_restore},
       else: :ok
  end

  defp validate_visual_layer(_row, :active), do: :ok

  defp validate_track(%{"is_override" => false} = row, _inherited) do
    cond do
      row["removed"] ->
        {:error, :local_definition_tombstone}

      not complete_mask?(row["overridden_fields"], @track_fields) ->
        {:error, :incomplete_local_definition}

      true ->
        :ok
    end
  end

  defp validate_track(%{"is_override" => true}, nil), do: {:error, :missing_inherited_identity}

  defp validate_track(%{"is_override" => true} = row, :removed) do
    if not row["removed"] and not complete_mask?(row["overridden_fields"], @track_fields),
      do: {:error, :incomplete_tombstone_restore},
      else: :ok
  end

  defp validate_track(%{"is_override" => true}, :active), do: :ok

  defp complete_mask?(fields, expected), do: MapSet.new(fields) == MapSet.new(expected)

  defp resource_key(row, :sequence_visual_layer), do: row["layer_key"]
  defp resource_key(row, :sequence_track), do: row["track_key"]

  defp resource_state(%{"removed" => true}), do: :removed
  defp resource_state(_row), do: :active

  defp invalid_resource(kind, owner_id, key, reason),
    do: {:error, {:invalid_sequence_resource_inheritance, kind, owner_id, key, reason}}
end
