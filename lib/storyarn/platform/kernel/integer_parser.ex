defmodule Storyarn.Platform.Kernel.IntegerParser do
  @moduledoc "Strict integer parsing for transport and serialized attribute boundaries."

  @spec parse(term()) :: integer() | nil
  def parse(""), do: nil
  def parse(nil), do: nil
  def parse(value) when is_integer(value), do: value

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  def parse(_value), do: nil

  @spec ensure(term()) :: integer()
  def ensure(value) when is_integer(value), do: value
  def ensure(_value), do: 0
end
