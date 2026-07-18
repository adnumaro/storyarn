defmodule Storyarn.Flows.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Projects.Project
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.TreeOperations, as: SharedTree

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
             ReferenceIntegrity.lock_flow_parent(project_id, nil, parent_id),
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
             ReferenceIntegrity.lock_active_flow_for_write(flow),
           {:ok, normalized_parent_id} <-
             ReferenceIntegrity.lock_flow_parent(
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
    SharedTree.next_position(Flow, project_id, parent_id)
  end

  @doc """
  Lists flows for a given parent (or root level).
  Excludes soft-deleted flows and orders by position then name.
  """
  def list_flows_by_parent(project_id, parent_id) do
    SharedTree.list_by_parent(Flow, project_id, parent_id)
  end

  defp reorder_locked_flows(project_id, parent_id, flow_ids) do
    case SharedTree.reorder(
           Flow,
           project_id,
           parent_id,
           flow_ids,
           &list_flows_by_parent/2
         ) do
      {:ok, flows} -> flows
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp move_locked_flow(flow, parent_id, position) do
    case SharedTree.move_to_position(
           Flow,
           flow,
           parent_id,
           position,
           &list_flows_by_parent/2
         ) do
      {:ok, updated_flow} -> updated_flow
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_project(project_id) when is_integer(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      nil -> {:error, :project_not_found}
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
    end
  end

  defp lock_project(_project_id), do: {:error, :project_not_found}

  defp normalize_flow_ids(flow_ids) do
    flow_ids
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, ids} ->
      case ProjectReferenceIntegrity.normalize_optional_id(value) do
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
      SharedTree.add_parent_filter(
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
