defmodule Storyarn.Flows.Evaluator.Helpers do
  @moduledoc """
  Shared helper functions for the flow evaluator and debug panel.
  """

  @doc "Strip HTML tags and truncate to `max_length` characters."
  @spec strip_html(binary() | nil, non_neg_integer()) :: String.t() | nil
  def strip_html(text, max_length \\ 40)
  def strip_html(nil, _), do: nil

  def strip_html(text, max_length) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> nil
      clean -> clean
    end
  end

  @doc "Format a debug value for display."
  @spec format_value(any()) :: String.t()
  def format_value(nil), do: "nil"
  def format_value(true), do: "true"
  def format_value(false), do: "false"
  def format_value(val) when is_list(val), do: Enum.join(val, ", ")

  def format_value(val) when is_binary(val) and byte_size(val) > 30,
    do: String.slice(val, 0, 30) <> "..."

  def format_value(val) when is_binary(val), do: val
  def format_value(val), do: to_string(val)
end
