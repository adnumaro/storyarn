defmodule Storyarn.Projects.References.Adapters.Flows.StaleVariableReferenceRepair do
  @moduledoc """
  Exact command adapter from Project-wide maintenance to the Flow writer.

  Projects preserves the established settings workflow and aggregate result,
  while Flows owns candidate interpretation, node JSON and every derivative of
  the resulting Flow mutation.
  """

  alias Storyarn.Flows

  @spec repair_project(map(), term()) :: {:ok, non_neg_integer()} | {:error, term()}
  def repair_project(scope, project_id), do: Flows.repair_stale_variable_references(scope, project_id)
end
