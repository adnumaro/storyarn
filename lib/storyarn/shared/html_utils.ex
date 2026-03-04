defmodule Storyarn.Shared.HtmlUtils do
  @moduledoc """
  HTML utility functions for stripping tags and decoding entities.

  Consolidates strip_html implementations used across the codebase.
  """

  @doc """
  Strips HTML tags and decodes common entities, returning plain text.

  Handles Tiptap HTML output (`<p>`, `<br>`, inline formatting).
  Newlines are inserted between block elements.

  ## Examples

      iex> strip_html("<p>Hello <strong>world</strong></p>")
      "Hello world"

      iex> strip_html("plain text")
      "plain text"

      iex> strip_html(nil)
      ""
  """
  @spec strip_html(String.t() | nil) :: String.t()
  def strip_html(nil), do: ""
  def strip_html(""), do: ""

  def strip_html(content) when is_binary(content) do
    content
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<\/p>\s*<p[^>]*>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_entities()
    |> String.trim()
  end

  @doc """
  Strips HTML tags and truncates to `max_length` characters.

  Returns `nil` if the result is empty after stripping.

  ## Examples

      iex> strip_and_truncate("<p>Hello world</p>", 5)
      "Hello"

      iex> strip_and_truncate(nil, 40)
      nil
  """
  @spec strip_and_truncate(String.t() | nil, non_neg_integer()) :: String.t() | nil
  def strip_and_truncate(text, max_length \\ 40)
  def strip_and_truncate(nil, _), do: nil

  def strip_and_truncate(text, max_length) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> nil
      clean -> clean
    end
  end

  # Decodes common HTML entities
  defp decode_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
  end
end
