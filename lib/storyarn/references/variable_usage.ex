defmodule Storyarn.References.VariableUsage do
  @moduledoc """
  Read-path adapter for variable reference usage and stale-reference repair.

  The SQL still lives in existing modules until the next PR2 pass moves it
  under this namespace.
  """

  alias Storyarn.Flows.VariableReferenceTracker

  defdelegate get_variable_usage(block_id, project_id), to: VariableReferenceTracker
  defdelegate count_variable_usage(block_id), to: VariableReferenceTracker
  defdelegate referenced_block_ids(block_ids), to: VariableReferenceTracker
  def check_stale_variable_references(block_id, project_id), do: VariableReferenceTracker.check_stale_references(block_id, project_id)
  def repair_stale_variable_references(project_id), do: VariableReferenceTracker.repair_stale_references(project_id)
  defdelegate list_stale_node_ids(flow_id), to: VariableReferenceTracker
end
