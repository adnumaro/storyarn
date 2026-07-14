defmodule Storyarn.Shared.HtmlUtils do
  @moduledoc """
  HTML utility functions for stripping tags and decoding entities.

  Consolidates strip_html implementations used across the codebase.
  """

  @heading_regex ~r/<(h[23])([^>]*)>\n?(.*?)<\/\1>/s
  @id_attribute_regex ~r/(?:^|\s)id\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/iu

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

  @doc """
  Counts words in text after stripping HTML tags.
  Returns 0 for nil or empty input.
  """
  @spec word_count(String.t() | nil) :: non_neg_integer()
  def word_count(nil), do: 0
  def word_count(""), do: 0

  def word_count(text) when is_binary(text) do
    text |> strip_html() |> String.split(~r/\s+/, trim: true) |> length()
  end

  @doc """
  Adds stable, unique IDs to h2 and h3 elements for anchor linking.

  IDs retain Unicode letters and numbers. Repeated headings receive a
  deterministic numeric suffix, and headings without usable text fall back to
  `section`.
  """
  @spec add_heading_ids(String.t()) :: String.t()
  def add_heading_ids(body) when is_binary(body) do
    {chunks, offset, _counts} =
      @heading_regex
      |> Regex.scan(body, return: :index)
      |> Enum.reduce({[], 0, %{}}, &replace_heading(body, &1, &2))

    tail = binary_part(body, offset, byte_size(body) - offset)
    IO.iodata_to_binary([Enum.reverse(chunks), tail])
  end

  defp replace_heading(
         body,
         [
           {match_start, match_length},
           {tag_start, tag_length},
           {attributes_start, attributes_length},
           {content_start, content_length}
         ],
         {chunks, offset, counts}
       ) do
    prefix = binary_part(body, offset, match_start - offset)
    tag = binary_part(body, tag_start, tag_length)
    attributes = binary_part(body, attributes_start, attributes_length)
    content = binary_part(body, content_start, content_length)
    {attributes, counts} = ensure_heading_id(attributes, content, counts)
    heading = ["<", tag, attributes, ">", content, "</", tag, ">"]

    {[[prefix, heading] | chunks], match_start + match_length, counts}
  end

  @doc """
  Extracts the h2/h3 outline from HTML after IDs have been assigned.

  Opening-tag attributes may appear in any order and IDs may use double,
  single, or unquoted attribute syntax.
  """
  @spec heading_outline(String.t()) :: [%{level: 2 | 3, id: String.t(), text: String.t()}]
  def heading_outline(body) when is_binary(body) do
    @heading_regex
    |> Regex.scan(body)
    |> Enum.flat_map(fn [_, tag, attributes, content] ->
      case id_attribute(attributes) do
        {:ok, id} when id != "" ->
          [%{level: if(tag == "h2", do: 2, else: 3), id: id, text: strip_html(content)}]

        _ ->
          []
      end
    end)
  end

  defp ensure_heading_id(attributes, content, counts) do
    case id_attribute(attributes) do
      {:ok, id} when id != "" ->
        {attributes, Map.update(counts, id, 1, &(&1 + 1))}

      existing_id ->
        {id, counts} = unique_heading_id(content, counts)
        {put_heading_id(attributes, existing_id, id), counts}
    end
  end

  defp put_heading_id(attributes, {:ok, ""}, id) do
    Regex.replace(@id_attribute_regex, attributes, " id=\"#{id}\"", global: false)
  end

  defp put_heading_id(attributes, :error, id), do: ~s( id="#{id}") <> attributes

  defp id_attribute(attributes) do
    case Regex.run(@id_attribute_regex, attributes, capture: :all_but_first) do
      captures when is_list(captures) ->
        {:ok, Enum.find(captures, "", &(&1 not in [nil, ""]))}

      nil ->
        :error
    end
  end

  defp unique_heading_id(content, counts) do
    base_id = heading_id(content)
    occurrence = Map.get(counts, base_id, 0) + 1
    id = if occurrence == 1, do: base_id, else: "#{base_id}-#{occurrence}"

    {id, Map.put(counts, base_id, occurrence)}
  end

  defp heading_id(content) do
    content
    |> strip_html()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s-]/u, "")
    |> String.trim()
    |> String.replace(~r/\s+/u, "-")
    |> case do
      "" -> "section"
      id -> id
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
