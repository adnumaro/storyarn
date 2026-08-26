defmodule Storyarn.Projects.FlowContentContract do
  @moduledoc """
  Defines the player-facing content that contributes to a Flow's runtime.

  The editor model contains additional node types and metadata which are not
  shipped as localizable runtime content.
  """

  @localizable_node_types ~w(dialogue exit)

  @spec localizable_node_types() :: [String.t()]
  def localizable_node_types, do: @localizable_node_types
end
