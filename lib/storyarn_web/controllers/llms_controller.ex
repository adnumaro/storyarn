defmodule StoryarnWeb.LlmsController do
  use StoryarnWeb, :controller

  alias Storyarn.Docs

  @summary "Storyarn is a narrative design platform for video games, branching dialogue, " <>
             "worldbuilding, scenes, localization, debugging, and engine-ready export."

  @audience_note "Storyarn's public documentation describes product concepts and workflows " <>
                   "for narrative designers, game designers, writers, and technical teams. " <>
                   "Authenticated workspace and project URLs are private application surfaces " <>
                   "and are intentionally omitted."

  @product_links [
    {"Storyarn", "/", "Product overview and open registration."},
    {"Documentation", "/docs", "Public product documentation and workflow guides."},
    {"Contact", "/contact", "Contact Storyarn."}
  ]

  @optional_links [
    {"Privacy Policy", "/privacy", "Privacy policy."},
    {"Terms of Service", "/terms", "Terms of service."},
    {"Sitemap", "/sitemap.xml", "Public sitemap for search crawlers."}
  ]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, IO.iodata_to_binary(llms_txt()))
  end

  defp llms_txt do
    [
      "# Storyarn\n\n",
      "> ",
      @summary,
      "\n\n",
      @audience_note,
      "\n\n",
      "## Product\n\n",
      link_list(@product_links),
      "\n",
      docs_sections(),
      "## Optional\n\n",
      link_list(@optional_links)
    ]
  end

  defp docs_sections do
    "en"
    |> Docs.list_guides()
    |> Enum.chunk_by(& &1.category_label)
    |> Enum.map(fn guides ->
      [first | _] = guides

      [
        "## ",
        first.category_label || first.category,
        "\n\n",
        Enum.map(guides, &guide_link/1),
        "\n"
      ]
    end)
  end

  defp guide_link(guide) do
    link_item(guide.title, "/docs/#{guide.url_path}", guide.description)
  end

  defp link_list(links) do
    Enum.map(links, fn {title, path, note} -> link_item(title, path, note) end)
  end

  defp link_item(title, path, note) do
    [
      "- [",
      markdown_link_text(title),
      "](",
      absolute_url(path),
      "): ",
      markdown_note(note),
      "\n"
    ]
  end

  defp absolute_url(path) do
    StoryarnWeb.Endpoint.url()
    |> URI.merge(path)
    |> URI.to_string()
  end

  defp markdown_link_text(value) do
    value
    |> to_string()
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
  end

  defp markdown_note(nil), do: ""

  defp markdown_note(value) do
    value
    |> to_string()
    |> String.replace("\n", " ")
    |> String.trim()
  end
end
