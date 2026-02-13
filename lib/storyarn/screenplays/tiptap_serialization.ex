defmodule Storyarn.Screenplays.TiptapSerialization do
  @moduledoc """
  Converts between ScreenplayElement records and TipTap document JSON.

  Server uses snake_case types (`scene_heading`), TipTap uses camelCase (`sceneHeading`).
  Atom nodes (page_break, conditional, etc.) have no inline content.
  Text nodes (action, dialogue, etc.) carry HTML content.
  """

  @server_to_tiptap %{
    "scene_heading" => "sceneHeading",
    "action" => "action",
    "character" => "character",
    "dialogue" => "dialogue",
    "parenthetical" => "parenthetical",
    "transition" => "transition",
    "note" => "note",
    "section" => "section",
    "page_break" => "pageBreak",
    "dual_dialogue" => "dualDialogue",
    "conditional" => "conditional",
    "instruction" => "instruction",
    "response" => "response",
    "hub_marker" => "hubMarker",
    "jump_marker" => "jumpMarker",
    "title_page" => "titlePage"
  }

  @tiptap_to_server Map.new(@server_to_tiptap, fn {k, v} -> {v, k} end)

  @atom_types ~w(page_break dual_dialogue conditional instruction response hub_marker jump_marker title_page)

  @doc """
  Converts a server element type (snake_case) to a TipTap node type (camelCase).

  Returns the input unchanged for unknown types.

  ## Examples

      iex> server_type_to_tiptap("scene_heading")
      "sceneHeading"

      iex> server_type_to_tiptap("unknown_type")
      "unknown_type"
  """
  @spec server_type_to_tiptap(String.t()) :: String.t()
  def server_type_to_tiptap(type), do: Map.get(@server_to_tiptap, type, type)

  @doc """
  Converts a TipTap node type (camelCase) to a server element type (snake_case).

  Returns the input unchanged for unknown types.

  ## Examples

      iex> tiptap_type_to_server("sceneHeading")
      "scene_heading"

      iex> tiptap_type_to_server("unknownType")
      "unknownType"
  """
  @spec tiptap_type_to_server(String.t()) :: String.t()
  def tiptap_type_to_server(type), do: Map.get(@tiptap_to_server, type, type)

  @doc """
  Converts a list of ScreenplayElement structs to a TipTap document JSON map.

  Elements are sorted by `position`. An empty list produces a document with
  a single empty action node (TipTap requires at least one block).

  ## Examples

      iex> elements_to_doc([%{type: "action", content: "Hello", ...}])
      %{"type" => "doc", "content" => [%{"type" => "action", "attrs" => ..., "content" => ...}]}
  """
  @spec elements_to_doc(list()) :: map()
  def elements_to_doc(elements) when is_list(elements) do
    content =
      elements
      |> Enum.sort_by(& &1.position)
      |> Enum.map(&element_to_node/1)

    content = if content == [], do: [empty_action_node()], else: content

    %{"type" => "doc", "content" => content}
  end

  @doc """
  Converts a TipTap document JSON map to a list of element attribute maps.

  Each map contains: `type` (snake_case), `position`, `content`, `data`, `element_id`.

  ## Examples

      iex> doc_to_element_attrs(%{"type" => "doc", "content" => [...]})
      [%{type: "action", position: 0, content: "Hello", data: %{}, element_id: nil}]
  """
  @spec doc_to_element_attrs(map()) :: [map()]
  def doc_to_element_attrs(%{"content" => content}) when is_list(content) do
    content
    |> Enum.with_index()
    |> Enum.map(fn {node, idx} -> node_to_attrs(node, idx) end)
  end

  def doc_to_element_attrs(_), do: []

  # -- Private: Element -> Node -----------------------------------------------

  defp element_to_node(element) do
    tiptap_type = server_type_to_tiptap(element.type)
    data = element.data || %{}

    attrs = %{
      "elementId" => element.id,
      "data" => data
    }

    # Character sheet reference: pass sheetId so the NodeView can render buttons
    attrs =
      if element.type == "character" && data["sheet_id"],
        do: Map.put(attrs, "sheetId", data["sheet_id"]),
        else: attrs

    base = %{"type" => tiptap_type, "attrs" => attrs}

    if element.type in @atom_types do
      base
    else
      Map.put(base, "content", html_to_inline_content(element.content))
    end
  end

  defp empty_action_node do
    %{
      "type" => "action",
      "attrs" => %{"elementId" => nil, "data" => %{}},
      "content" => []
    }
  end

  # -- Private: Node -> Element attrs -----------------------------------------

  defp node_to_attrs(node, position) do
    server_type = tiptap_type_to_server(node["type"] || "action")

    %{
      type: server_type,
      position: position,
      content: inline_content_to_html(node["content"]),
      data: get_in(node, ["attrs", "data"]) || %{},
      element_id: get_in(node, ["attrs", "elementId"])
    }
  end

  # -- Private: HTML <-> TipTap inline content --------------------------------

  # Plain text is stored as-is for backward compatibility. When content
  # contains `<span class="mention">` tags (inline sheet references),
  # Floki parses the HTML into mixed text + mention TipTap nodes.

  defp html_to_inline_content(nil), do: []
  defp html_to_inline_content(""), do: []

  defp html_to_inline_content(content) when is_binary(content) do
    if String.contains?(content, "<span") do
      case Floki.parse_fragment(content) do
        {:ok, tree} -> parse_inline_tree(tree)
        _ -> [%{"type" => "text", "text" => content}]
      end
    else
      [%{"type" => "text", "text" => content}]
    end
  end

  defp parse_inline_tree(nodes) do
    Enum.flat_map(nodes, fn
      text when is_binary(text) ->
        if text == "", do: [], else: [%{"type" => "text", "text" => text}]

      {"span", attrs, children} ->
        parse_inline_span(Map.new(attrs), attrs, children)

      {tag, tag_attrs, children} ->
        text = Floki.text({tag, tag_attrs, children})
        if text == "", do: [], else: [%{"type" => "text", "text" => text}]
    end)
  end

  defp parse_inline_span(attrs_map, attrs, children) do
    if mention_span?(attrs_map) do
      [
        %{
          "type" => "mention",
          "attrs" => %{
            "id" => attrs_map["data-id"] || "",
            "label" => attrs_map["data-label"] || "",
            "type" => attrs_map["data-type"] || "sheet"
          }
        }
      ]
    else
      text = Floki.text({"span", attrs, children})
      if text == "", do: [], else: [%{"type" => "text", "text" => text}]
    end
  end

  defp mention_span?(%{"class" => class}), do: String.contains?(class, "mention")
  defp mention_span?(_), do: false

  defp inline_content_to_html(nil), do: ""
  defp inline_content_to_html([]), do: ""

  defp inline_content_to_html(content) when is_list(content) do
    has_mentions = Enum.any?(content, &match?(%{"type" => "mention"}, &1))

    if has_mentions do
      Enum.map_join(content, "", fn
        %{"type" => "text", "text" => text} ->
          escape_html(text)

        %{"type" => "mention", "attrs" => attrs} ->
          id = escape_attr(attrs["id"] || "")
          label_attr = escape_attr(attrs["label"] || "")
          type = escape_attr(attrs["type"] || "sheet")
          label_text = escape_html(attrs["label"] || "")

          ~s(<span class="mention" data-type="#{type}" data-id="#{id}" data-label="#{label_attr}">##{label_text}</span>)

        _ ->
          ""
      end)
    else
      Enum.map_join(content, "", fn
        %{"type" => "text", "text" => text} -> text
        _ -> ""
      end)
    end
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(val), do: escape_html(to_string(val))

  defp escape_attr(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(val), do: escape_attr(to_string(val))
end
