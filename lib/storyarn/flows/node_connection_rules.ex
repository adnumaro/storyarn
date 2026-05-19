defmodule Storyarn.Flows.NodeConnectionRules do
  @moduledoc """
  Shared flow graph validation rules.

  These rules separate executable graph nodes from visual/organizational nodes.
  Annotations and sequences can exist without graph edges, so they must not
  pollute flow health, dashboards, or export validation.
  """

  @connection_optional_types ~w(annotation sequence)
  @terminal_output_types ~w(exit jump)

  @doc "Node types that are allowed to have no graph connections."
  @spec connection_optional_types() :: [String.t()]
  def connection_optional_types, do: @connection_optional_types

  @doc "Returns true when a node type should not be reported as connectionless."
  @spec connection_optional_type?(String.t()) :: boolean()
  def connection_optional_type?(type), do: type in @connection_optional_types

  @doc "Returns true when a node type can be reported as unreachable from Entry."
  @spec can_be_unreachable?(String.t()) :: boolean()
  def can_be_unreachable?(type), do: type not in ["entry" | @connection_optional_types]

  @doc "Returns true when a node type is expected to have at least one outgoing connection."
  @spec needs_outgoing_connection?(String.t()) :: boolean()
  def needs_outgoing_connection?(type), do: type not in (@terminal_output_types ++ @connection_optional_types)
end
