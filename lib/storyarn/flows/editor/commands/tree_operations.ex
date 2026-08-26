defmodule Storyarn.Flows.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor.Adapters.TreePositionStore
  alias Storyarn.Flows.Editor.Data.ProjectRecord
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.References
  alias Storyarn.Repo

  @doc """
  Reorders flows within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of flow IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, flows}` with the reordered flows or `{:error, reason}`.
  """
  def reorder_flows(project_id, parent_id, flow_ids) when is_list(flow_ids) do
    Repo.transaction(fn ->
      with {:ok, _project} <- lock_project(project_id),
           {:ok, normalized_parent_id} <-
             References.lock_flow_parent(project_id, nil, parent_id),
           {:ok, normalized_flow_ids} <- normalize_flow_ids(flow_ids),
           :ok <-
             lock_reordered_flows(project_id, normalized_parent_id, normalized_flow_ids) do
        reorder_locked_flows(project_id, normalized_parent_id, normalized_flow_ids)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Moves a flow to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the flow's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, flow}` with the moved flow or `{:error, reason}`.
  """
  def move_flow_to_position(%Flow{} = flow, new_parent_id, new_position) do
    Repo.transaction(fn ->
      with {:ok, %{flow: locked_flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow),
           {:ok, normalized_parent_id} <-
             References.lock_flow_parent(
               project_id,
               locked_flow.id,
               new_parent_id
             ) do
        move_locked_flow(locked_flow, normalized_parent_id, new_position)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Gets the next available position for a new flow in the given container.
  """
  def next_position(project_id, parent_id) do
    from(flow in Flow,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      select: max(flow.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  @doc """
  Lists flows for a given parent (or root level).
  Excludes soft-deleted flows and orders by position then name.
  """
  def list_flows_by_parent(project_id, parent_id) do
    from(flow in Flow,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      order_by: [asc: flow.position, asc: flow.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end

  defp reorder_locked_flows(project_id, parent_id, flow_ids) do
    flow_ids
    |> Enum.with_index()
    |> batch_set_positions(project_id, parent_id)

    list_flows_by_parent(project_id, parent_id)
  end

  defp move_locked_flow(flow, parent_id, position) do
    position = max(position, 0)

    case flow
         |> Flow.move_changeset(%{parent_id: parent_id, position: position})
         |> Repo.update() do
      {:ok, updated_flow} ->
        apply_move(flow, updated_flow, parent_id, position)

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp apply_move(flow, updated_flow, parent_id, position) do
    destination_pairs =
      flow.project_id
      |> list_flows_by_parent(parent_id)
      |> Enum.reject(&(&1.id == flow.id))
      |> List.insert_at(position, updated_flow)
      |> Enum.with_index()
      |> Enum.map(fn {sibling, index} -> {sibling.id, index} end)

    batch_set_positions(destination_pairs, flow.project_id, parent_id)

    if flow.parent_id != parent_id do
      reorder_source_container(flow.project_id, flow.parent_id)
    end

    Repo.get!(Flow, flow.id)
  end

  defp reorder_source_container(project_id, parent_id) do
    project_id
    |> list_flows_by_parent(parent_id)
    |> Enum.with_index()
    |> Enum.map(fn {flow, index} -> {flow.id, index} end)
    |> batch_set_positions(project_id, parent_id)
  end

  defp batch_set_positions([], _project_id, _parent_id), do: :ok

  defp batch_set_positions(id_position_pairs, project_id, parent_id) do
    TreePositionStore.update!(id_position_pairs, project_id, parent_id)
  end

  @doc false
  def build_tree_from_flat_list(flows) do
    grouped = Enum.group_by(flows, & &1.parent_id)
    build_subtree(grouped, nil)
  end

  defp build_subtree(grouped, parent_id) do
    Enum.map(Map.get(grouped, parent_id, []), fn flow ->
      Map.put(flow, :children, build_subtree(grouped, flow.id))
    end)
  end

  defp add_parent_filter(query, nil), do: where(query, [flow], is_nil(flow.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [flow], flow.parent_id == ^parent_id)

  defp lock_project(project_id) when is_integer(project_id) do
    case Repo.one(from(project in ProjectRecord, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      nil -> {:error, :project_not_found}
      %ProjectRecord{deleted_at: nil} = project -> {:ok, project}
      %ProjectRecord{} -> {:error, :project_not_active}
    end
  end

  defp lock_project(_project_id), do: {:error, :project_not_found}

  defp normalize_flow_ids(flow_ids) do
    flow_ids
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, ids} ->
      case References.normalize_optional_id(value) do
        {:ok, id} when is_integer(id) -> {:cont, {:ok, [id | ids]}}
        _other -> {:halt, {:error, :invalid_flow_order}}
      end
    end)
    |> case do
      {:ok, ids} ->
        ids = Enum.reverse(ids)

        if length(ids) == length(Enum.uniq(ids)),
          do: {:ok, ids},
          else: {:error, :invalid_flow_order}

      {:error, _reason} = error ->
        error
    end
  end

  defp lock_reordered_flows(_project_id, _parent_id, []), do: :ok

  defp lock_reordered_flows(project_id, parent_id, flow_ids) do
    query =
      add_parent_filter(
        from(flow in Flow,
          where: flow.id in ^flow_ids and flow.project_id == ^project_id and is_nil(flow.deleted_at),
          order_by: [asc: flow.id],
          lock: "FOR UPDATE",
          select: flow.id
        ),
        parent_id
      )

    if query |> Repo.all() |> length() == length(flow_ids),
      do: :ok,
      else: {:error, :flows_not_found}
  end
end
