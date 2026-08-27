defmodule Storyarn.Scenes.Exploration.Execution.NumericValues do
  @moduledoc false

  def parse(nil), do: 0.0
  def parse(number) when is_integer(number), do: number / 1
  def parse(number) when is_float(number), do: number

  def parse(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> 0.0
    end
  end

  def parse(_value), do: 0.0

  def format(number) when is_float(number) do
    if number == Float.floor(number) and number >= -1.0e15 and number <= 1.0e15,
      do: trunc(number),
      else: number
  end

  def format(value), do: value
end
