defmodule Storyarn.Screenplays.Import.Fountain do
  @moduledoc """
  Parses a Fountain-formatted string into a list of element attribute maps.

  Each map contains `type`, `content`, `data`, and `position` fields ready
  for insertion via `Screenplays.create_element/2`.

  Supports title page key-value headers, all standard Fountain element types,
  forced prefixes (`.`, `!`, `@`, `>`), dual dialogue (`^`), and Fountain mark
  conversion to HTML (bold, italic, bold-italic).
  """

  @scene_heading_pattern ~r/^(INT\.|EXT\.|EST\.|INT\.?\/?EXT\.?|I\/E\.?)\s/i
  @transition_pattern ~r/^.+TO:$/

  @title_keys %{
    "title" => "title",
    "credit" => "credit",
    "author" => "author",
    "authors" => "author",
    "source" => "source",
    "draft date" => "draft_date",
    "contact" => "contact"
  }

  @doc """
  Parses a Fountain text string into a list of element attribute maps.

  Returns a list of `%{type: String.t(), content: String.t(), data: map(), position: integer()}`.

  ## Examples

      iex> parse("INT. OFFICE - DAY\\n\\nJOHN walks in.")
      [
        %{type: "scene_heading", content: "INT. OFFICE - DAY", data: %{}, position: 0},
        %{type: "action", content: "JOHN walks in.", data: %{}, position: 1}
      ]
  """
  @spec parse(String.t()) :: [map()]
  def parse(text) when is_binary(text) do
    text = String.trim(text)

    if text == "" do
      []
    else
      {title_data, body_text} = extract_title_page(text)
      body_elements = parse_body(body_text)
      title_elements = build_title_elements(title_data)

      (title_elements ++ body_elements)
      |> Enum.with_index()
      |> Enum.map(fn {el, idx} -> %{el | position: idx} end)
    end
  end

  def parse(_), do: []

  defp build_title_elements(data) when data == %{}, do: []

  defp build_title_elements(data),
    do: [%{type: "title_page", content: "", data: data, position: 0}]

  # -- Title page extraction --------------------------------------------------

  defp extract_title_page(text) do
    lines = String.split(text, "\n")

    case lines do
      [first | _] ->
        if Regex.match?(~r/^[A-Za-z][A-Za-z\s]*:/, first) do
          extract_title_lines(lines)
        else
          {%{}, text}
        end

      _ ->
        {%{}, text}
    end
  end

  defp extract_title_lines(lines) do
    {title_lines, rest} = split_at_first_blank(lines)

    data = Enum.reduce(title_lines, %{}, &parse_title_line/2)
    body = Enum.join(rest, "\n")
    {data, body}
  end

  defp parse_title_line(line, acc) do
    case Regex.run(~r/^([A-Za-z][A-Za-z\s]*?):\s*(.*)$/, line) do
      [_, key, value] ->
        normalized = String.downcase(String.trim(key))
        field = Map.get(@title_keys, normalized)
        if field, do: Map.put(acc, field, String.trim(value)), else: acc

      _ ->
        acc
    end
  end

  defp split_at_first_blank(lines) do
    case Enum.find_index(lines, &(&1 == "")) do
      nil -> {lines, []}
      idx -> {Enum.take(lines, idx), Enum.drop(lines, idx + 1)}
    end
  end

  # -- Body parsing -----------------------------------------------------------

  defp parse_body(""), do: []

  defp parse_body(text) do
    text = String.trim(text)
    if text == "", do: [], else: do_parse_body(text)
  end

  defp do_parse_body(text) do
    paragraphs = split_paragraphs_with_indent(text)
    profile = detect_indent_profile(paragraphs)

    Enum.flat_map(paragraphs, fn {indent, content} ->
      classify_one(indent, content, profile)
    end)
  end

  defp split_paragraphs_with_indent(text) do
    Regex.split(~r/\n\s*\n/, text)
    |> Enum.map(fn raw ->
      first_line = raw |> String.split("\n") |> hd()
      {leading_spaces(first_line), String.trim(raw)}
    end)
    |> Enum.reject(fn {_, c} -> c == "" end)
  end

  defp leading_spaces(line) do
    byte_size(line) - byte_size(String.trim_leading(line))
  end

  # Detect indent profile for the document.
  # Returns nil for non-indented docs, or %{action: n, dialogue: n, character: n}
  defp detect_indent_profile(paragraphs) do
    indents = Enum.map(paragraphs, &elem(&1, 0))
    min_indent = Enum.min(indents, fn -> 0 end)
    max_indent = Enum.max(indents, fn -> 0 end)

    if max_indent - min_indent <= 10, do: nil, else: build_indent_profile(paragraphs, min_indent)
  end

  defp build_indent_profile(paragraphs, min_indent) do
    # ALL CAPS short lines well above base indent → character names
    char_indents =
      paragraphs
      |> Enum.filter(fn {indent, content} ->
        first = content |> String.split("\n") |> hd()

        indent > min_indent + 5 and all_upper?(first) and
          String.length(first) < 50 and String.length(first) > 1
      end)
      |> Enum.map(&elem(&1, 0))

    if char_indents == [] do
      nil
    else
      {char_level, _} = char_indents |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1))
      # Dialogue sits between action and character indent
      dialogue_min = min_indent + 3
      char_min = max(div(char_level + min_indent, 2), min_indent + 5)

      %{action_max: dialogue_min, dialogue_min: dialogue_min, character_min: char_min}
    end
  end

  # -- Single paragraph classification ----------------------------------------

  defp classify_one(indent, paragraph, profile) do
    classify_structural(paragraph) || classify_text(indent, paragraph, profile)
  end

  defp classify_structural(paragraph) do
    cond do
      page_break?(paragraph) -> [make_el("page_break", "")]
      section?(paragraph) -> [make_section(paragraph)]
      note?(paragraph) -> [make_note(paragraph)]
      forced_scene_heading?(paragraph) -> [make_forced_heading(paragraph)]
      scene_heading?(paragraph) -> [make_el("scene_heading", paragraph)]
      true -> nil
    end
  end

  defp classify_text(indent, paragraph, profile) do
    cond do
      forced_transition?(paragraph) ->
        [make_forced_transition(paragraph)]

      transition?(paragraph) ->
        [make_el("transition", paragraph)]

      centered_text?(paragraph) ->
        [make_centered(paragraph)]

      character_paragraph?(indent, paragraph, profile) ->
        parse_dialogue_elements(paragraph)

      indented_dialogue_zone?(indent, profile) ->
        classify_indented_dialogue(paragraph)

      forced_action?(paragraph) ->
        [make_forced_action(paragraph)]

      true ->
        [make_el("action", paragraph)]
    end
  end

  defp indented_dialogue_zone?(_indent, nil), do: false

  defp indented_dialogue_zone?(indent, profile),
    do: indent >= profile.dialogue_min and indent < profile.character_min

  defp classify_indented_dialogue(paragraph) do
    first_line = paragraph |> String.split("\n") |> hd() |> String.trim()

    if String.starts_with?(first_line, "("),
      do: [make_el("parenthetical", paragraph)],
      else: [make_el("dialogue", paragraph)]
  end

  defp page_break?(p), do: p == "===" or String.starts_with?(p, "===")
  defp section?(p), do: String.starts_with?(p, "#")

  defp note?(p),
    do: String.starts_with?(p, "[[") and String.ends_with?(p, "]]")

  defp forced_scene_heading?(p),
    do: String.starts_with?(p, ".") and not String.starts_with?(p, "..")

  defp scene_heading?(p), do: Regex.match?(@scene_heading_pattern, p)

  defp forced_transition?(p),
    do: String.starts_with?(p, ">") and not String.ends_with?(p, "<")

  defp transition?(p),
    do: (Regex.match?(@transition_pattern, p) or String.trim(p) == "FADE IN:") and all_upper?(p)

  defp centered_text?(p),
    do: String.starts_with?(p, ">") and String.ends_with?(p, "<")

  defp character_paragraph?(indent, paragraph, profile) do
    lines =
      paragraph
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    first = hd(lines)

    if profile != nil do
      # Indented document: indent is the primary signal
      indent >= profile.character_min and character_line?(first)
    else
      # Non-indented (plain Fountain): require dialogue in same paragraph
      length(lines) > 1 and character_line?(first)
    end
  end

  defp forced_action?(p), do: String.starts_with?(p, "!")

  defp make_el(type, content),
    do: %{type: type, content: convert_marks(content), data: %{}, position: 0}

  defp make_section(paragraph) do
    {level, text} = parse_section(paragraph)
    %{type: "section", content: convert_marks(text), data: %{"level" => level}, position: 0}
  end

  defp make_note(paragraph) do
    text = paragraph |> String.trim_leading("[[") |> String.trim_trailing("]]") |> String.trim()
    make_el("note", text)
  end

  defp make_forced_heading(paragraph) do
    text = String.trim_leading(paragraph, ".")
    make_el("scene_heading", text)
  end

  defp make_forced_transition(paragraph) do
    text = String.trim_leading(paragraph, ">") |> String.trim()
    make_el("transition", text)
  end

  defp make_forced_action(paragraph) do
    text = String.trim_leading(paragraph, "!")
    make_el("action", text)
  end

  defp make_centered(paragraph) do
    text =
      paragraph
      |> String.trim_leading(">")
      |> String.trim_trailing("<")
      |> String.trim()

    make_el("action", text)
  end

  # -- Character/dialogue parsing (state machine) ----------------------------

  defp character_line?(line) do
    line = String.trim(line)
    clean = strip_dual_marker(line)

    cond do
      clean == "" -> false
      ends_with_punctuation?(clean) -> false
      String.starts_with?(clean, "@") -> true
      all_upper?(clean) and not Regex.match?(@transition_pattern, clean) -> true
      true -> false
    end
  end

  defp ends_with_punctuation?(text),
    do: String.ends_with?(text, [":", ".", "!", ","])

  defp strip_dual_marker(line) do
    if String.ends_with?(line, "^"),
      do: String.trim(String.trim_trailing(line, "^")),
      else: line
  end

  defp parse_dialogue_elements(paragraph) do
    lines = String.split(paragraph, "\n") |> Enum.map(&String.trim/1)
    {char_name, dual?} = parse_character_name(hd(lines))

    char_data = if dual?, do: %{"dual" => true}, else: %{}

    char_el = %{
      type: "character",
      content: convert_marks(char_name),
      data: char_data,
      position: 0
    }

    inline_lines = tl(lines) |> Enum.reject(&(&1 == ""))

    if inline_lines == [] do
      # Indented document: character alone in paragraph, dialogue is next paragraph
      [char_el]
    else
      [char_el | parse_inline_dialogue(inline_lines)]
    end
  end

  defp parse_inline_dialogue([first | rest_lines]) do
    if String.starts_with?(first, "(") do
      paren_el = make_el("parenthetical", first)

      if rest_lines == [] do
        [paren_el]
      else
        [paren_el, make_el("dialogue", Enum.join(rest_lines, "\n"))]
      end
    else
      make_dialogue_from_lines([first | rest_lines])
    end
  end

  defp make_dialogue_from_lines(lines), do: [make_el("dialogue", Enum.join(lines, "\n"))]

  defp parse_character_name(line) do
    line = String.trim(line)
    line = if String.starts_with?(line, "@"), do: String.trim_leading(line, "@"), else: line

    if String.ends_with?(line, "^") do
      {String.trim(String.trim_trailing(line, "^")), true}
    else
      {line, false}
    end
  end

  # -- Section parsing --------------------------------------------------------

  defp parse_section(text) do
    {hashes, rest} =
      text
      |> String.graphemes()
      |> Enum.split_while(&(&1 == "#"))

    level = length(hashes)
    content = rest |> Enum.join("") |> String.trim()
    {level, content}
  end

  # -- Fountain marks → HTML --------------------------------------------------

  defp convert_marks(text) when is_binary(text) do
    text
    |> convert_bold_italic()
    |> convert_bold()
    |> convert_italic()
  end

  defp convert_marks(text), do: text

  defp convert_bold_italic(text) do
    Regex.replace(~r/\*\*\*(.+?)\*\*\*/, text, "<strong><em>\\1</em></strong>")
  end

  defp convert_bold(text) do
    Regex.replace(~r/\*\*(.+?)\*\*/, text, "<strong>\\1</strong>")
  end

  defp convert_italic(text) do
    Regex.replace(~r/\*(.+?)\*/, text, "<em>\\1</em>")
  end

  # -- Helpers ----------------------------------------------------------------

  defp all_upper?(text) do
    stripped = Regex.replace(~r/[^a-zA-Z]/, text, "")
    stripped != "" and stripped == String.upcase(stripped)
  end
end
