defmodule Storyarn.Shared.TimeHelpers do
  @moduledoc """
  Shared time utilities.
  """

  @doc """
  Returns the current UTC time truncated to seconds.

  Replaces the common `DateTime.utc_now() |> DateTime.truncate(:second)` pattern
  used across schemas and CRUD modules for timestamps.
  """
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
