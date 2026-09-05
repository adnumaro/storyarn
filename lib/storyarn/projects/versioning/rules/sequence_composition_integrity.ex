defmodule Storyarn.Projects.Versioning.SequenceCompositionIntegrity do
  @moduledoc false

  alias Storyarn.Flows

  @doc false
  @spec validate_nodes([map()]) :: :ok | {:error, term()}
  defdelegate validate_nodes(nodes), to: Flows, as: :validate_sequence_composition_nodes
end
