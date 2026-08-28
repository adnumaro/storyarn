defmodule Storyarn.Scenes.Severity do
  @moduledoc false

  @catalog [:error, :warning, :info]

  def rank(:error), do: 0
  def rank(:warning), do: 1
  def rank(:info), do: 2
  def rank("error"), do: 0
  def rank("warning"), do: 1
  def rank("info"), do: 2

  def rank(other) do
    raise ArgumentError,
          "unknown Scene severity #{inspect(other)}; expected one of #{inspect(@catalog)} (atom or string)"
  end
end
