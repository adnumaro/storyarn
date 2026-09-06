defmodule Storyarn.Flows.Editor.Commands.SequenceWrap do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.SequenceCreate
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @spec wrap_selection_in_sequence(Flow.t(), [integer()], map()) ::
          {:ok, FlowNode.t()} | {:error, atom() | Ecto.Changeset.t()}
  def wrap_selection_in_sequence(flow, node_ids, attrs \\ %{})

  def wrap_selection_in_sequence(%Flow{}, [], _attrs), do: {:error, :empty_selection}

  def wrap_selection_in_sequence(%Flow{id: flow_id}, node_ids, attrs) when is_list(node_ids) do
    fn ->
      with {:ok, %{flow: locked_flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow_id),
           {:ok, nodes} <- load_active_nodes(locked_flow.id, node_ids),
           {:ok, parent_id} <- common_parent_id(nodes),
           attrs = build_wrap_attrs(attrs, parent_id),
           {sequence, ^project_id} <- SequenceCreate.insert_in_transaction(locked_flow.id, attrs),
           :ok <- assign_nodes_to_sequence(nodes, sequence.id) do
        {sequence, project_id}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  defp load_active_nodes(flow_id, node_ids) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^node_ids and node.flow_id == ^flow_id and is_nil(node.deleted_at),
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    if length(nodes) == length(Enum.uniq(node_ids)) do
      {:ok, nodes}
    else
      {:error, :nodes_not_found}
    end
  end

  defp common_parent_id(nodes) do
    case nodes |> Enum.map(& &1.parent_id) |> Enum.uniq() do
      [parent_id] -> {:ok, parent_id}
      _ -> {:error, :mixed_parents}
    end
  end

  defp build_wrap_attrs(attrs, parent_id) do
    attrs
    |> normalize_keys()
    |> Map.put_new("name", "Sequence")
    |> Map.put("parent_id", parent_id)
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp assign_nodes_to_sequence(nodes, sequence_id) do
    ids = Enum.map(nodes, & &1.id)

    Repo.update_all(from(node in FlowNode, where: node.id in ^ids), set: [parent_id: sequence_id])
    :ok
  end

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result
end
