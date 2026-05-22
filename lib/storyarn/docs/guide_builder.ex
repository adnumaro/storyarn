defmodule Storyarn.Docs.GuideBuilder do
  @moduledoc false

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
    |> add_heading_ids()
  end

  # Add id attributes to h2 and h3 tags for anchor linking.
  defp add_heading_ids(body) do
    String.replace(body, ~r/<(h[23])>\n?(.*?)<\/\1>/s, fn full ->
      case Regex.run(~r/<(h[23])>\n?(.*?)<\/\1>/s, full) do
        [_, tag, content] ->
          id = heading_to_id(content)
          "<#{tag} id=\"#{id}\">#{content}</#{tag}>"

        _ ->
          full
      end
    end)
  end

  # Extract h2/h3 headings into a TOC list: [{level, id, text}, ...]
  defp extract_toc(body) do
    ~r/<(h[23])\s+id="([^"]+)">(.*?)<\/\1>/s
    |> Regex.scan(body)
    |> Enum.map(fn [_, tag, id, content] ->
      level = if tag == "h2", do: 2, else: 3
      text = strip_html(content)
      %{level: level, id: id, text: text}
    end)
  end

  defp heading_to_id(content) do
    content
    |> strip_html()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
  end
end
