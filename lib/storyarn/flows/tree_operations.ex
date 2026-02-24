defmodule Storyarn.Flows.TreeOperations do
  @moduledoc false

  alias Storyarn.Flows.Flow
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
    if new_parent_id && SharedTree.descendant?(Flow, new_parent_id, flow.id) do
      {:error, :cyclic_parent}
    else
      SharedTree.move_to_position(
        Flow,
        flow,
        new_parent_id,
        new_position,
        &list_flows_by_parent/2
      )
    end
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
end
