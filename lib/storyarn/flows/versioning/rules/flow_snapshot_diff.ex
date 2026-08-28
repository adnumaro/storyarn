defmodule Storyarn.Flows.Versioning.FlowSnapshotDiff do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  @node_ignore_fields ["position_x", "position_y", "original_id"]

  @spec diff(map(), map()) :: [map()]
  def diff(old_snapshot, new_snapshot) when is_map(old_snapshot) and is_map(new_snapshot) do
    []
    |> check_field_change(old_snapshot, new_snapshot, "name", dgettext("flows", "Renamed flow"))
    |> check_field_change(old_snapshot, new_snapshot, "shortcut", dgettext("flows", "Changed shortcut"))
    |> check_field_change(old_snapshot, new_snapshot, "description", dgettext("flows", "Changed description"))
    |> check_field_change(old_snapshot, new_snapshot, "scene_id", dgettext("flows", "Changed scene"))
    |> check_field_change(old_snapshot, new_snapshot, "settings", dgettext("flows", "Changed settings"))
    |> diff_nodes_and_connections(
      old_snapshot["nodes"] || [],
      new_snapshot["nodes"] || [],
      old_snapshot["connections"] || [],
      new_snapshot["connections"] || []
    )
    |> Enum.reverse()
  end

  defp check_field_change(changes, old_snapshot, new_snapshot, field, detail) do
    if old_snapshot[field] == new_snapshot[field],
      do: changes,
      else: [%{category: :property, action: :modified, detail: detail} | changes]
  end

  defp diff_nodes_and_connections(changes, old_nodes, new_nodes, old_connections, new_connections) do
    old_positions = node_position_map(old_nodes)
    new_positions = node_position_map(new_nodes)

    key_fns = [
      & &1["original_id"],
      fn node ->
        technical_id = get_in(node, ["data", "technical_id"])
        if technical_id && technical_id != "", do: {node["type"], technical_id}
      end,
      fn node ->
        index =
          Map.get(old_positions, node_identity(node)) ||
            Map.get(new_positions, node_identity(node))

        if is_integer(index), do: {:type_position, node["type"], index}
      end
    ]

    {matched, added, removed} = match_by_keys(old_nodes, new_nodes, key_fns)
    {old_parent_tokens, new_parent_tokens} = parent_identity_tokens(matched)

    modified =
      Enum.filter(matched, fn {old_node, new_node} ->
        normalize_node(old_node, old_parent_tokens) !=
          normalize_node(new_node, new_parent_tokens)
      end)

    old_node_index = old_nodes |> Enum.with_index() |> Map.new()
    new_node_index = new_nodes |> Enum.with_index() |> Map.new()

    old_index_to_new =
      Enum.reduce(matched, %{}, fn {old_node, new_node}, indexes ->
        old_index = Map.get(old_node_index, old_node)
        new_index = Map.get(new_node_index, new_node)

        if is_integer(old_index) and is_integer(new_index),
          do: Map.put(indexes, old_index, new_index),
          else: indexes
      end)

    changes
    |> append_node_changes(added, :added)
    |> append_node_changes(removed, :removed)
    |> append_modified_nodes(modified)
    |> diff_connections(old_connections, new_connections, old_index_to_new)
  end

  defp parent_identity_tokens(matched) do
    matched
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}}, fn {{old_node, new_node}, token}, {old_tokens, new_tokens} ->
      {
        maybe_put_parent_token(old_tokens, old_node["original_id"], token),
        maybe_put_parent_token(new_tokens, new_node["original_id"], token)
      }
    end)
  end

  defp maybe_put_parent_token(tokens, nil, _token), do: tokens
  defp maybe_put_parent_token(tokens, node_id, token), do: Map.put(tokens, node_id, token)

  defp normalize_node(node, parent_tokens) do
    node
    |> Map.drop(@node_ignore_fields)
    |> Map.update("parent_id", nil, &Map.get(parent_tokens, &1, {:unmatched_parent, &1}))
  end

  defp append_node_changes(changes, nodes, action) do
    Enum.reduce(nodes, changes, fn node, acc ->
      type = node["type"] || "unknown"

      detail =
        case action do
          :added -> dgettext("flows", "Added %{type} node", type: type)
          :removed -> dgettext("flows", "Removed %{type} node", type: type)
        end

      [%{category: :node, action: action, detail: detail} | acc]
    end)
  end

  defp append_modified_nodes(changes, modified) do
    Enum.reduce(modified, changes, fn {_old_node, new_node}, acc ->
      [
        %{
          category: :node,
          action: :modified,
          detail: dgettext("flows", "Modified %{type} node", type: new_node["type"] || "unknown")
        }
        | acc
      ]
    end)
  end

  defp diff_connections(changes, old_connections, new_connections, old_index_to_new) do
    remapped_old =
      old_connections
      |> Enum.with_index()
      |> Enum.map(fn {connection, index} ->
        source_index = Map.get(old_index_to_new, connection["source_node_index"])
        target_index = Map.get(old_index_to_new, connection["target_node_index"])

        if is_integer(source_index) and is_integer(target_index) do
          connection
          |> Map.put("source_node_index", source_index)
          |> Map.put("target_node_index", target_index)
        else
          connection
          |> Map.put("source_node_index", {:removed, index})
          |> Map.put("target_node_index", {:removed, index})
        end
      end)

    key_fn = fn connection ->
      {
        connection["source_node_index"],
        connection["target_node_index"],
        connection["source_pin"],
        connection["target_pin"]
      }
    end

    {matched, added, removed} = match_by_keys(remapped_old, new_connections, [key_fn])
    modified = Enum.filter(matched, fn {old, new} -> old["label"] != new["label"] end)

    changes
    |> append_connection_changes(added, :added)
    |> append_connection_changes(removed, :removed)
    |> append_modified_connections(modified)
  end

  defp append_connection_changes(changes, connections, action) do
    Enum.reduce(connections, changes, fn _connection, acc ->
      detail =
        case action do
          :added -> dgettext("flows", "Added connection")
          :removed -> dgettext("flows", "Removed connection")
        end

      [%{category: :connection, action: action, detail: detail} | acc]
    end)
  end

  defp append_modified_connections(changes, modified) do
    Enum.reduce(modified, changes, fn _pair, acc ->
      [
        %{
          category: :connection,
          action: :modified,
          detail: dgettext("flows", "Modified connection")
        }
        | acc
      ]
    end)
  end

  defp match_by_keys(old_list, new_list, key_fns) do
    {matched, remaining_old, remaining_new} =
      Enum.reduce(key_fns, {[], old_list, new_list}, fn key_fn, {matched, old, new} ->
        match_round(old, new, key_fn, matched)
      end)

    {Enum.reverse(matched), remaining_new, remaining_old}
  end

  defp match_round(old_list, new_list, key_fn, matched) do
    old_keyed =
      old_list
      |> Enum.map(&{key_fn.(&1), &1})
      |> Enum.reject(fn {key, _item} -> is_nil(key) end)
      |> Map.new()

    {new_matched, consumed_keys} =
      new_list
      |> Enum.map(&{key_fn.(&1), &1})
      |> Enum.reject(fn {key, _item} -> is_nil(key) end)
      |> Enum.reduce({matched, MapSet.new()}, fn {key, new_item}, {acc, consumed} ->
        case Map.get(old_keyed, key) do
          nil -> {acc, consumed}
          old_item -> {[{old_item, new_item} | acc], MapSet.put(consumed, key)}
        end
      end)

    remaining_old =
      Enum.reject(old_list, fn item ->
        key = key_fn.(item)
        not is_nil(key) and MapSet.member?(consumed_keys, key)
      end)

    remaining_new =
      Enum.reject(new_list, fn item ->
        key = key_fn.(item)
        not is_nil(key) and MapSet.member?(consumed_keys, key)
      end)

    {new_matched, remaining_old, remaining_new}
  end

  defp node_identity(node), do: {node["type"], node["position_x"], node["position_y"]}

  defp node_position_map(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, index}, positions ->
      Map.put_new(positions, node_identity(node), index)
    end)
  end
end
