defmodule Storyarn.Screenplays.ContentUtils do
  @moduledoc """
  Utility functions for handling HTML/plain-text content in screenplay elements.

  Provides stripping, detection, and conversion between HTML and plain text.
  """

  @doc """
  Strips HTML tags and decodes common entities, returning plain text.

  Delegates to `Storyarn.Shared.HtmlUtils.strip_html/1`.
  """
  @spec strip_html(String.t() | nil) :: String.t()
  defdelegate strip_html(content), to: Storyarn.Shared.HtmlUtils

  @doc """
  Detects if content contains HTML tags.

  ## Examples

      iex> html?("<p>Hello</p>")
      true

      iex> html?("plain text")
      false
  """
  @spec html?(String.t() | nil) :: boolean()
  def html?(nil), do: false
  def html?(""), do: false
  def html?(content) when is_binary(content), do: Regex.match?(~r/<[a-z][^>]*>/i, content)

  @doc """
  Sanitizes HTML content by stripping unsafe tags, event-handler attributes,
  and dangerous URI schemes.

  Delegates to `Storyarn.Shared.HtmlSanitizer.sanitize_html/1`.
  """
  @spec sanitize_html(String.t() | nil) :: String.t()
  defdelegate sanitize_html(content), to: Storyarn.Shared.HtmlSanitizer

  @doc """
  Wraps plain text in `<p>` tags for TipTap.

  ## Examples

      iex> plain_to_html("Hello world")
      "<p>Hello world</p>"
  """
  @spec plain_to_html(String.t() | nil) :: String.t()
  def plain_to_html(nil), do: "<p></p>"
  def plain_to_html(""), do: "<p></p>"

  def plain_to_html(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("", fn line -> "<p>#{encode_entities(line)}</p>" end)
  end

  # Encodes characters for HTML
  defp encode_entities(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
