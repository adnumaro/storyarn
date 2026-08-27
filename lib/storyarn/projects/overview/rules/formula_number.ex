defmodule Storyarn.Projects.Overview.FormulaNumber do
  @moduledoc """
  Projects-owned numeric coercion for Sheet formula health and resolution.

  The permissive zero fallback and whole-float compaction are formula semantics,
  not general map utilities. They are duplicated here so Platform does not own
  Projects' interpretation of Sheet cell values.
  """

  @spec parse(term()) :: float()
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

  @spec format_result(term()) :: term()
  def format_result(number) when is_float(number) do
    if number == Float.floor(number) and number >= -1.0e15 and number <= 1.0e15,
      do: trunc(number),
      else: number
  end

  def format_result(value), do: value
end
