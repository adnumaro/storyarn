defmodule Storyarn.Sheets.Health.Contracts.Severity do
  @moduledoc """
  Closed ordering contract for Sheet health severities.

  Both atom and serialized string values rank identically so presentation
  adapters can sort findings without defining a second severity catalog.
  """

  @catalog [:error, :warning, :info]

  def rank(:error), do: 0
  def rank(:warning), do: 1
  def rank(:info), do: 2
  def rank("error"), do: 0
  def rank("warning"), do: 1
  def rank("info"), do: 2

  def rank(other) do
    raise ArgumentError,
          "unknown Sheet severity #{inspect(other)}; expected one of #{inspect(@catalog)} (atom or string)"
  end
end
