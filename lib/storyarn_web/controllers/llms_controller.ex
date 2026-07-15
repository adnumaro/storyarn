defmodule StoryarnWeb.LlmsController do
  use StoryarnWeb, :controller

  alias Storyarn.Blog
  alias Storyarn.Docs
  alias Storyarn.Localization.Languages
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  @summary "Storyarn is a narrative design platform for video games, branching dialogue, " <>
             "worldbuilding, scenes, localization, debugging, and engine-ready export."

  @audience_note "Storyarn's public documentation describes product concepts and workflows " <>
                   "for narrative designers, game designers, writers, and technical teams. " <>
                   "Authenticated workspace and project URLs are private application surfaces " <>
                   "and are intentionally omitted."

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
      Enum.map(PublicLocales.locales(), &locale_section/1),
      "## Optional\n\n",
      link_item("Sitemap", "/sitemap.xml", "Public sitemap for search crawlers.")
    ]
  end

  defp locale_section(locale) do
    [
      "## ",
      locale_name(locale),
      " (",
      PublicLocales.language_tag(locale),
      ")\n\n",
      "### Product\n\n",
      product_links(locale),
      articles_section(locale),
      docs_section(locale)
    ]
  end

  defp product_links(locale) do
    links = [
      {"Storyarn", PublicURLs.home_path(locale), "Product overview and open registration."},
      {"Contact", PublicURLs.contact_path(locale), "Contact Storyarn."},
      {"Privacy Policy", PublicURLs.privacy_path(locale), "Privacy policy."},
      {"Terms of Service", PublicURLs.terms_path(locale), "Terms of service."}
    ]

    links =
      if locale in Blog.published_locales() do
        List.insert_at(
          links,
          1,
          {"Blog", PublicURLs.blog_index_path(locale),
           "Practical articles about narrative design and production workflows."}
        )
      else
        links
      end

    link_list(links)
  end

  defp articles_section(locale) do
    case Blog.list_posts(locale) do
      [] ->
        []

      posts ->
        [
          "\n### Articles\n\n",
          Enum.map(posts, fn post ->
            link_item(
              post.title,
              PublicURLs.blog_post_path(post.locale, post.slug),
              post.description
            )
          end)
        ]
    end
  end

  defp docs_section(locale) do
    case Docs.list_guides(locale) do
      [] ->
        []

      guides ->
        [
          "\n### Documentation\n\n",
          guides
          |> Enum.chunk_by(& &1.category_label)
          |> Enum.map(fn category_guides ->
            [first | _] = category_guides

            [
              "#### ",
              first.category_label || first.category,
              "\n\n",
              Enum.map(category_guides, fn guide ->
                link_item(
                  guide.title,
                  PublicURLs.docs_path(locale, guide),
                  guide.description
                )
              end),
              "\n"
            ]
          end)
        ]
    end
  end

  defp locale_name(locale) do
    case locale |> PublicLocales.language_tag() |> Languages.get() do
      %{native: native} -> native
      nil -> locale |> PublicLocales.language_tag() |> String.upcase()
    end
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
