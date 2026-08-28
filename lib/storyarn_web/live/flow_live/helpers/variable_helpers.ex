defmodule StoryarnWeb.FlowLive.Helpers.VariableHelpers do
  @moduledoc false

  alias Storyarn.Flows

  @doc """
  Returns the flat list of all variable descriptors (sheets + pins + zones).
  Used by LiveViews that pass variables to condition/instruction builders.

  Delegates so this set cannot drift from the one the health checkers use.
  """
  defdelegate list_all_variables(project_id), to: Flows, as: :list_referenceable_variables

  @doc "Compatibility adapter for Flow Web callers not yet moved to the facade directly."
  defdelegate build_variables(project_id), to: Flows, as: :build_runtime_variables
end
