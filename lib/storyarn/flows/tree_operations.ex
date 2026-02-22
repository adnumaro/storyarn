defmodule Storyarn.Flows.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Shared.TreeOperations, as: SharedTree

  @doc """
  Reorders flows within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of flow IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, flows}` with the reordered flows or `{:error, reason}`.
  """
  def reorder_flows(project_id, parent_id, flow_ids) when is_list(flow_ids) do
    SharedTree.reorder(Flow, project_id, parent_id, flow_ids, &list_flows_by_parent/2)
  end

  @doc """
  Moves a flow to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the flow's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, flow}` with the moved flow or `{:error, reason}`.
  """
  def move_flow_to_position(%Flow{} = flow, new_parent_id, new_position) do
    Repo.transaction(fn ->
      old_parent_id = flow.parent_id
      project_id = flow.project_id

      # Update the flow's parent and position
      {:ok, updated_flow} =
        flow
        |> Flow.move_changeset(%{parent_id: new_parent_id, position: new_position})
        |> Repo.update()

      # Get all siblings in the destination container (including the moved flow)
      siblings = list_flows_by_parent(project_id, new_parent_id)

      # Build the new order: insert the moved flow at the desired position
      siblings_without_moved = Enum.reject(siblings, &(&1.id == flow.id))

      new_order =
        siblings_without_moved
        |> List.insert_at(new_position, updated_flow)
        |> Enum.map(& &1.id)

      # Update positions in destination container
      new_order
      |> Enum.with_index()
      |> Enum.each(fn {flow_id, index} ->
        SharedTree.update_position_only(Flow, flow_id, index)
      end)

      # If parent changed, also reorder the source container
      if old_parent_id != new_parent_id do
        SharedTree.reorder_source_container(
          Flow,
          project_id,
          old_parent_id,
          &list_flows_by_parent/2
        )
      end

      # Return the flow with updated position
      Repo.get!(Flow, flow.id)
    end)
  end

  @doc """
  Gets the next available position for a new flow in the given container.
  """
  def next_position(project_id, parent_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      select: max(f.position)
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  @doc """
  Lists flows for a given parent (or root level).
  Excludes soft-deleted flows and orders by position then name.
  """
  def list_flows_by_parent(project_id, parent_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      order_by: [asc: f.position, asc: f.name]
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.all()
  end
end
