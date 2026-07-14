defmodule Storyarn.Docs.GuideBuilder do
  @moduledoc false

  alias Storyarn.Shared.HtmlUtils

  def build(filename, attrs, body) do
    parts =
      filename
      |> Path.rootname()
      |> Path.split()

    [locale, category | doc_parts] = docs_parts(parts)
    raw_slug = List.last(doc_parts)
    section_parts = Enum.drop(doc_parts, -1)
    slug = String.replace(raw_slug, ~r/^\d+-/, "")
    path = section_parts ++ [slug]

    body = post_process(body)
    toc = extract_toc(body)

    %{
      slug: slug,
      path: path,
      url_path: Enum.join([category | path], "/"),
      locale: locale,
      title: attrs[:title],
      category: category,
      category_label: attrs[:category_label],
      section: section_id(section_parts),
      section_label: attrs[:section_label] || section_label(section_parts),
      section_order: attrs[:section_order] || section_order(section_parts),
      order: attrs[:order],
      description: attrs[:description],
      body: body,
      toc: toc
    }
  end

  defp docs_parts(parts) do
    case Enum.drop_while(parts, &(&1 != "docs")) do
      ["docs" | docs_parts] -> docs_parts
      _ -> Enum.take(parts, -3)
    end
  end

  defp section_id([]), do: nil
  defp section_id(parts), do: Enum.join(parts, "/")

  defp section_label([]), do: nil

  defp section_label(parts) do
    parts
    |> List.last()
    |> String.split("-")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp section_order([]), do: 0
  defp section_order(_parts), do: 1

  defp post_process(body) do
    body
    |> String.replace(~r/\{accent\}(.*?)\{\/accent\}/s, "<span class=\"docs-accent\">\\1</span>")
    |> HtmlUtils.add_heading_ids()
  end

  # Extract h2/h3 headings into a TOC list: [{level, id, text}, ...]
  defp extract_toc(body) do
    ~r/<(h[23])\s+id="([^"]+)">(.*?)<\/\1>/s
    |> Regex.scan(body)
    |> Enum.map(fn [_, tag, id, content] ->
      level = if tag == "h2", do: 2, else: 3
      text = HtmlUtils.strip_html(content)
      %{level: level, id: id, text: text}
    end)
  end
end
