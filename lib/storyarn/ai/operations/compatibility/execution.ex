defmodule Storyarn.AI.Execution do
  @moduledoc """
  Compatibility boundary for the former combined AI execution pipeline.

  New callers use `Storyarn.AI`. This module keeps the established
  `preflight/1` and `execute/1` entry points while Routing and Operations own
  their respective workflows internally.
  """

  defdelegate preflight(intent), to: Storyarn.AI
  defdelegate execute(intent), to: Storyarn.AI
end
