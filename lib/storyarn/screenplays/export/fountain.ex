defmodule Storyarn.Screenplays.Export.Fountain do
  @moduledoc """
  Converts a list of ScreenplayElement structs to a Fountain-formatted string.

  Handles HTML→Fountain mark conversion (bold, italic, strikethrough),
  mention references, and all standard screenplay element types.

  Interactive types (conditional, instruction, response, hub_marker, jump_marker)
  are silently stripped from the output.
  """

  alias Storyarn.Screenplays.ContentUtils

  @skip_types ~w(conditional instruction response hub_marker jump_marker)

  @title_page_keys ~w(title credit author source draft_date contact)

  @doc """
  Exports a list of screenplay elements to a Fountain-formatted string.

  Elements are sorted by position. Title page elements are converted to
  Fountain key-value headers. Interactive types are silently omitted.

  ## Examples

      iex> export([%{type: "action", content: "He walks.", position: 0}])
      "He walks.\\n"
  """
  @spec export([map()]) :: String.t()
  def export(elements) when is_list(elements) do
    sorted = Enum.sort_by(elements, & &1.position)
    {title_pages, body} = Enum.split_with(sorted, &(&1.type == "title_page"))
    body = Enum.reject(body, &(&1.type in @skip_types))

    title_block = format_title_page(List.first(title_pages))
    body_block = format_body(body)

    join_blocks(title_block, body_block)
  end

  def export(_), do: ""

  # -- Title page -------------------------------------------------------------

  defp format_title_page(nil), do: ""

  defp format_title_page(element) do
    data = element.data || %{}

    lines =
      @title_page_keys
      |> Enum.flat_map(fn key ->
        value = data[key]

        if value && String.trim(value) != "" do
          label = title_key_label(key)
          ["#{label}: #{String.trim(value)}"]
        else
          []
        end
      end)

    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n") <> "\n"
    end
  end

  defp title_key_label("title"), do: "Title"
  defp title_key_label("credit"), do: "Credit"
  defp title_key_label("author"), do: "Author"
  defp title_key_label("source"), do: "Source"
  defp title_key_label("draft_date"), do: "Draft date"
  defp title_key_label("contact"), do: "Contact"
  defp title_key_label(key), do: String.capitalize(key)

  # -- Body -------------------------------------------------------------------

  defp format_body([]), do: ""

  defp format_body(elements) do
    Enum.map_join(elements, "", &format_element/1)
  end

  # -- Element formatting -----------------------------------------------------

  defp format_element(%{type: "scene_heading"} = el) do
    "\n#{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "action"} = el) do
    "\n#{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "character"} = el) do
    "\n#{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "parenthetical"} = el) do
    text = convert_content(el.content)
    text = ensure_parens(text)
    "#{text}\n"
  end

  defp format_element(%{type: "dialogue"} = el) do
    "#{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "transition"} = el) do
    "\n#{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "page_break"}) do
    "\n===\n"
  end

  defp format_element(%{type: "section"} = el) do
    data = el.data || %{}
    level = data["level"] || 1
    prefix = String.duplicate("#", level)
    "\n#{prefix} #{convert_content(el.content)}\n"
  end

  defp format_element(%{type: "note"} = el) do
    "\n[[#{convert_content(el.content)}]]\n"
  end

  defp format_element(%{type: "dual_dialogue"} = el) do
    data = el.data || %{}
    left = data["left"] || %{}
    right = data["right"] || %{}

    left_lines =
      ["\n#{left["character"] || ""}\n"] ++
        paren_line(left["parenthetical"]) ++
        ["#{left["dialogue"] || ""}\n"]

    right_lines =
      ["\n#{right["character"] || ""} ^\n"] ++
        paren_line(right["parenthetical"]) ++
        ["#{right["dialogue"] || ""}\n"]

    Enum.join(left_lines ++ right_lines, "")
  end

  defp format_element(%{type: "title_page"}), do: ""
  defp format_element(_), do: ""

  # -- Content conversion -----------------------------------------------------

  defp convert_content(nil), do: ""
  defp convert_content(""), do: ""

  defp convert_content(content) do
    if ContentUtils.html?(content) do
      case Floki.parse_fragment(content) do
        {:ok, tree} -> convert_html_tree(tree)
        _ -> content
      end
    else
      content
    end
  end

  defp convert_html_tree(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &convert_html_node/1)
  end

  defp convert_html_node(text) when is_binary(text), do: text

  defp convert_html_node({"strong", _, children}) do
    "**#{convert_html_tree(children)}**"
  end

  defp convert_html_node({"b", _, children}) do
    "**#{convert_html_tree(children)}**"
  end

  defp convert_html_node({"em", _, children}) do
    "*#{convert_html_tree(children)}*"
  end

  defp convert_html_node({"i", _, children}) do
    "*#{convert_html_tree(children)}*"
  end

  defp convert_html_node({"s", _, children}) do
    convert_html_tree(children)
  end

  defp convert_html_node({"del", _, children}) do
    convert_html_tree(children)
  end

  defp convert_html_node({"br", _, _}), do: "\n"

  defp convert_html_node({"span", attrs, children}) do
    attrs_map = Map.new(attrs)

    if mention_span?(attrs_map) do
      attrs_map["data-label"] || convert_html_tree(children)
    else
      convert_html_tree(children)
    end
  end

  defp convert_html_node({_tag, _, children}) do
    convert_html_tree(children)
  end

  defp mention_span?(%{"class" => class}), do: String.contains?(class, "mention")
  defp mention_span?(_), do: false

  # -- Helpers ----------------------------------------------------------------

  defp paren_line(nil), do: []
  defp paren_line(""), do: []
  defp paren_line(text), do: ["#{ensure_parens(text)}\n"]

  defp ensure_parens(text) do
    text = String.trim(text)
    text = if String.starts_with?(text, "("), do: text, else: "(#{text}"
    if String.ends_with?(text, ")"), do: text, else: "#{text})"
  end

  defp join_blocks("", ""), do: ""
  defp join_blocks(title, ""), do: title
  defp join_blocks("", body), do: body
  defp join_blocks(title, body), do: title <> "\n" <> body
end
