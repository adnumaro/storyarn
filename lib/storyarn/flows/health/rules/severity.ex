defmodule Storyarn.Flows.Severity do
  @moduledoc """
  Flow-owned ordering for the health severity vocabulary.

  Other tools may currently use the same three labels, but that coincidence is
  not a shared domain contract. Flows owns how its findings are ranked.
  """

  @catalog [:error, :warning, :info]

  @spec rank(atom() | String.t()) :: 0..2
  def rank(:error), do: 0
  def rank(:warning), do: 1
  def rank(:info), do: 2
  def rank("error"), do: 0
  def rank("warning"), do: 1
  def rank("info"), do: 2

  def rank(other) do
    raise ArgumentError,
          "unknown Flow severity #{inspect(other)}; expected one of #{inspect(@catalog)} (atom or string)"
  end

  @spec catalog() :: [atom()]
  def catalog, do: @catalog
end
