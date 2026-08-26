defmodule Storyarn.Flows.NodeCrud do
  @moduledoc """
  Compatibility boundary for the established Flow node API.

  Reads are owned by `Storyarn.Flows.Editor.Queries.Nodes`; mutations remain
  in the Editor command modules. Keeping this module declarative preserves its
  stable identity without letting read projections depend on commands.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor.Queries.Nodes
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCreate
  alias Storyarn.Flows.NodeDelete
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Flows.References
  alias Storyarn.Repo

  defdelegate list_nodes(flow_id), to: Nodes
  defdelegate list_runtime_nodes(flow_id), to: Nodes
  defdelegate get_node(flow_id, node_id), to: Nodes
  defdelegate get_node!(flow_id, node_id), to: Nodes
  defdelegate get_node_by_id!(flow_id, node_id), to: Nodes
  defdelegate hub_id_exists?(flow_id, hub_id, exclude_node_id), to: Nodes
  defdelegate list_hubs(flow_id), to: Nodes
  defdelegate get_hub_by_hub_id(flow_id, hub_id), to: Nodes
  defdelegate list_referencing_jumps(flow_id, hub_id), to: Nodes
  defdelegate list_dialogue_nodes_by_speaker(project_id, sheet_id), to: Nodes
  defdelegate count_nodes_by_type(flow_id), to: Nodes
  defdelegate list_exit_nodes_for_flow(flow_id), to: Nodes
  defdelegate list_outcome_tags_for_project(project_id), to: Nodes
  defdelegate list_subflow_nodes_referencing(flow_id, project_id), to: Nodes
  defdelegate list_nodes_referencing_flow(flow_id, project_id), to: Nodes
  defdelegate batch_resolve_subflow_data(nodes, project_id \\ nil), to: Nodes
  defdelegate resolve_subflow_data(data, subflow_cache), to: Nodes
  defdelegate batch_resolve_exit_data(nodes, project_id \\ nil), to: Nodes
  defdelegate resolve_exit_data(data), to: Nodes
  defdelegate resolve_exit_data(data, project_id), to: Nodes
  defdelegate resolve_exit_data(data, project_id, exit_cache), to: Nodes
  defdelegate safe_to_integer(value), to: Nodes

  @doc false
  def lock_flow_nodes_for_update(%Flow{} = flow) do
    with {:ok, %{flow: locked_flow}} <-
           References.lock_active_flow_for_write(flow, :key_share) do
      nodes =
        Repo.all(
          from(node in FlowNode,
            where: node.flow_id == ^locked_flow.id and is_nil(node.deleted_at),
            order_by: [asc: node.id]
          )
        )

      {:ok, {locked_flow, nodes}}
    end
  end

  defdelegate create_node(flow, attrs), to: NodeCreate
  defdelegate create_node_without_dashboard_broadcast(flow, attrs), to: NodeCreate
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: NodeCreate

  defdelegate update_node(node, attrs), to: NodeUpdate
  defdelegate update_node_without_dashboard_broadcast(node, attrs), to: NodeUpdate
  defdelegate update_node_position(node, attrs), to: NodeUpdate
  defdelegate update_node_parent(node, parent_id), to: NodeUpdate
  defdelegate batch_update_positions(flow_id, positions), to: NodeUpdate
  defdelegate update_node_data(node, data), to: NodeUpdate
  defdelegate update_node_data_without_dashboard_broadcast(node, data), to: NodeUpdate
  defdelegate edit_node(flow_id, node_id, operation, payload), to: NodeUpdate
  defdelegate data_and_derivatives_current?(node, data, project_id), to: NodeUpdate
  defdelegate data_and_derivatives_current_ids(node_data_pairs, project_id), to: NodeUpdate
  defdelegate change_node(node, attrs \\ %{}), to: NodeUpdate

  defdelegate delete_node(node), to: NodeDelete
  defdelegate delete_node_without_dashboard_broadcast(node), to: NodeDelete
  defdelegate delete_node_in_transaction_without_dashboard_broadcast(node), to: NodeDelete
  defdelegate restore_node(flow_id, node_id), to: NodeDelete
end
