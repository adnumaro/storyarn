defmodule Storyarn.Projects.References.Adapters.Flows.StaleVariableReferenceRepair do
  @moduledoc """
  Exact command adapter from Project-wide maintenance to the Flow writer.

  Projects preserves the established settings workflow and aggregate result,
  while Flows owns candidate interpretation, node JSON and every derivative of
  the resulting Flow mutation.
  """

  alias Storyarn.Flows

  @spec repair_project(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  def repair_project(project_id), do: Flows.repair_stale_variable_references(project_id)
end
