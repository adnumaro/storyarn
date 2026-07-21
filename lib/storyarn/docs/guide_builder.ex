defmodule Storyarn.Docs.GuideBuilder do
  @moduledoc false

  alias Storyarn.Publication.HtmlLinkLocalizer
  alias Storyarn.Publication.Locales
  alias Storyarn.Shared.HtmlUtils

  def build(filename, attrs, body) do
    parts =
      filename
      |> Path.rootname()
      |> Path.split()

    [locale, category | doc_parts] = docs_parts(parts)
    validate_public_locale!(locale)
    raw_slug = List.last(doc_parts)
    section_parts = Enum.drop(doc_parts, -1)
    slug = String.replace(raw_slug, ~r/^\d+-/, "")
    path = section_parts ++ [slug]

    body = post_process(body, locale)
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
      feature_flag: attrs[:feature_flag],
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

  defp post_process(body, locale) do
    body
    |> String.replace(~r/\{accent\}(.*?)\{\/accent\}/s, "<span class=\"docs-accent\">\\1</span>")
    |> HtmlUtils.add_heading_ids()
    |> HtmlLinkLocalizer.localize_navigation(locale)
  end

  defp validate_public_locale!(locale) do
    if !Locales.valid?(locale) do
      raise ArgumentError, "docs locale must be published publicly, got: #{inspect(locale)}"
    end
  end

  # Extract h2/h3 headings into a TOC list: [{level, id, text}, ...]
  defp extract_toc(body), do: HtmlUtils.heading_outline(body)
end
