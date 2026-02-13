defmodule Storyarn.Screenplays.ContentUtils do
  @moduledoc """
  Utility functions for handling HTML/plain-text content in screenplay elements.

  Provides stripping, detection, and conversion between HTML and plain text.
  """

  @doc """
  Strips HTML tags and decodes common entities, returning plain text.

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
    |> String.replace(~r/<[^>]*>/, "")
    |> decode_entities()
    |> String.trim()
  end

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

  # Tags that TipTap can produce. Anything outside this list is stripped.
  @tiptap_allowed_tags ~w(p br b i em strong u s del a span div)

  @doc """
  Sanitizes HTML content by stripping unsafe tags and event-handler attributes.

  Keeps only the tags TipTap can produce (`p`, `br`, inline formatting, etc.)
  and removes any `on*` event attributes or `javascript:` URLs.

  ## Examples

      iex> sanitize_html("<p>Hello</p>")
      "<p>Hello</p>"

      iex> sanitize_html("<script>alert('xss')</script><p>Safe</p>")
      "alert(&#39;xss&#39;)<p>Safe</p>"

      iex> sanitize_html(nil)
      ""
  """
  @spec sanitize_html(String.t() | nil) :: String.t()
  def sanitize_html(nil), do: ""
  def sanitize_html(""), do: ""

  def sanitize_html(content) when is_binary(content) do
    case Floki.parse_document(content) do
      {:ok, tree} ->
        tree
        |> strip_unsafe_nodes()
        |> Floki.raw_html()

      _ ->
        Phoenix.HTML.html_escape(content) |> Phoenix.HTML.safe_to_string()
    end
  end

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

  # Strips tags not in @tiptap_allowed_tags, keeping their text children.
  defp strip_unsafe_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &strip_unsafe_node/1)
  end

  defp strip_unsafe_node({tag, attrs, children}) do
    if tag in @tiptap_allowed_tags do
      safe_attrs = Enum.reject(attrs, fn {k, v} -> unsafe_attr?(k, v) end)
      [{tag, safe_attrs, strip_unsafe_nodes(children)}]
    else
      strip_unsafe_nodes(children)
    end
  end

  defp strip_unsafe_node(text) when is_binary(text), do: [text]
  defp strip_unsafe_node({:comment, _}), do: []
  defp strip_unsafe_node(_), do: []

  defp unsafe_attr?(name, value) when is_binary(name) do
    downcased = String.downcase(name)

    String.starts_with?(downcased, "on") ||
      downcased in ~w(srcdoc formaction) ||
      (is_binary(value) and String.contains?(String.downcase(value), "javascript:"))
  end

  defp unsafe_attr?(_name, _value), do: false

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
