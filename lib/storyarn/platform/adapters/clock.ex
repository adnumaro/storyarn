defmodule Storyarn.Platform.Shared.TimeHelpers do
  @moduledoc """
  Policy-neutral wall-clock adapter used to obtain canonical UTC timestamps.

  The stable module name is retained for callers while the implementation lives
  with Platform's technical adapters.
  """

  @doc """
  Returns the current UTC time truncated to seconds.

  Replaces the common `DateTime.utc_now() |> DateTime.truncate(:second)` pattern
  used across schemas and CRUD modules for timestamps.
  """
  @spec now() :: DateTime.t()
  def now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
