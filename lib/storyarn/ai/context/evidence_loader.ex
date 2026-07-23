defmodule Storyarn.AI.Context.EvidenceLoader do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @spec load(pos_integer(), [map()]) :: {:ok, [map()]} | {:error, :context_missing}
  def load(project_id, evidence) when is_integer(project_id) and is_list(evidence) do
    loaded = load_requested_evidence(project_id, ids_by_type(evidence))
    materialize_evidence(evidence, loaded)
  end

  defp ids_by_type(evidence) do
    evidence
    |> Enum.group_by(&value(&1, :type), &value(&1, :id))
    |> Map.new(fn {type, ids} -> {type, Enum.uniq(ids)} end)
  end

  defp load_requested_evidence(project_id, ids_by_type) do
    %{}
    |> load_flows(project_id, Map.get(ids_by_type, "flow", []))
    |> load_nodes(project_id, Map.get(ids_by_type, "flow_node", []))
    |> load_connections(project_id, Map.get(ids_by_type, "flow_connection", []))
    |> load_sheets(project_id, Map.get(ids_by_type, "sheet", []))
    |> load_blocks(project_id, Map.get(ids_by_type, "sheet_block", []))
  end

  defp materialize_evidence(evidence, loaded) do
    evidence
    |> Enum.sort_by(&{value(&1, :type), value(&1, :id)})
    |> Enum.reduce_while({:ok, []}, &materialize_descriptor(&1, &2, loaded))
    |> reverse_materialized()
  end

  defp materialize_descriptor(descriptor, {:ok, acc}, loaded) do
    key = {value(descriptor, :type), value(descriptor, :id)}

    case Map.fetch(loaded, key) do
      {:ok, item} -> {:cont, {:ok, [item | acc]}}
      :error -> {:halt, {:error, :context_missing}}
    end
  end

  defp reverse_materialized({:ok, items}), do: {:ok, Enum.reverse(items)}
  defp reverse_materialized({:error, :context_missing} = error), do: error

  defp load_flows(loaded, _project_id, []), do: loaded

  defp load_flows(loaded, project_id, ids) do
    from(flow in Flow,
      where: flow.project_id == ^project_id and flow.id in ^ids and is_nil(flow.deleted_at)
    )
    |> Repo.all()
    |> Enum.reduce(loaded, fn flow, acc ->
      put_loaded(
        acc,
        "flow",
        flow.id,
        %{
          "name" => flow.name,
          "shortcut" => flow.shortcut,
          "description" => flow.description
        },
        flow.updated_at
      )
    end)
  end

  defp load_nodes(loaded, _project_id, []), do: loaded

  defp load_nodes(loaded, project_id, ids) do
    from(node in FlowNode,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and node.id in ^ids and
          is_nil(flow.deleted_at) and is_nil(node.deleted_at),
      select: node
    )
    |> Repo.all()
    |> Enum.reduce(loaded, fn node, acc ->
      put_loaded(
        acc,
        "flow_node",
        node.id,
        %{
          "flow_id" => node.flow_id,
          "type" => node.type,
          "data" => node.data
        },
        node.updated_at
      )
    end)
  end

  defp load_connections(loaded, _project_id, []), do: loaded

  defp load_connections(loaded, project_id, ids) do
    from(connection in FlowConnection,
      join: flow in Flow,
      on: flow.id == connection.flow_id,
      join: source in FlowNode,
      on: source.id == connection.source_node_id,
      join: target in FlowNode,
      on: target.id == connection.target_node_id,
      where:
        flow.project_id == ^project_id and connection.id in ^ids and
          is_nil(flow.deleted_at) and is_nil(source.deleted_at) and is_nil(target.deleted_at),
      select: connection
    )
    |> Repo.all()
    |> Enum.reduce(loaded, fn connection, acc ->
      put_loaded(
        acc,
        "flow_connection",
        connection.id,
        %{
          "flow_id" => connection.flow_id,
          "source_node_id" => connection.source_node_id,
          "source_pin" => connection.source_pin,
          "target_node_id" => connection.target_node_id,
          "target_pin" => connection.target_pin,
          "label" => connection.label
        },
        connection.updated_at
      )
    end)
  end

  defp load_sheets(loaded, _project_id, []), do: loaded

  defp load_sheets(loaded, project_id, ids) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id and sheet.id in ^ids and is_nil(sheet.deleted_at)
    )
    |> Repo.all()
    |> Enum.reduce(loaded, fn sheet, acc ->
      put_loaded(
        acc,
        "sheet",
        sheet.id,
        %{
          "name" => sheet.name,
          "shortcut" => sheet.shortcut,
          "description" => sheet.description
        },
        sheet.updated_at
      )
    end)
  end

  defp load_blocks(loaded, _project_id, []), do: loaded

  defp load_blocks(loaded, project_id, ids) do
    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and block.id in ^ids and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      select: block
    )
    |> Repo.all()
    |> Enum.reduce(loaded, fn block, acc ->
      put_loaded(
        acc,
        "sheet_block",
        block.id,
        %{
          "sheet_id" => block.sheet_id,
          "type" => block.type,
          "label" => get_in(block.config, ["label"]),
          "value" => block.value,
          "variable_name" => block.variable_name
        },
        block.updated_at
      )
    end)
  end

  defp put_loaded(loaded, type, id, content, revision) do
    Map.put(loaded, {type, id}, %{
      type: type,
      id: id,
      content: content,
      revision: revision
    })
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
