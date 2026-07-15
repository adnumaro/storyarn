defmodule StoryarnWeb.SitemapController do
  use StoryarnWeb, :controller

  alias Storyarn.Blog
  alias Storyarn.Docs
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  @static_path_functions [:home_path, :contact_path, :privacy_path, :terms_path]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, sitemap_xml())
  end

  defp sitemap_xml do
    urls =
      @static_path_functions
      |> Enum.flat_map(&static_entries/1)
      |> Kernel.++(docs_entries())
      |> Kernel.++(blog_entries())
      |> Enum.uniq_by(& &1.path)
      |> Enum.map(&url_entry/1)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n),
      urls,
      ~s(</urlset>\n)
    ]
  end

  defp static_entries(path_function) do
    locale_paths =
      Enum.map(PublicLocales.locales(), fn locale ->
        {locale, apply(PublicURLs, path_function, [locale])}
      end)

    entries_for_locale_paths(locale_paths)
  end

  defp docs_entries do
    PublicLocales.locales()
    |> Enum.flat_map(&Docs.list_guides/1)
    |> Enum.group_by(& &1.url_path)
    |> Enum.flat_map(fn {_url_path, guides} ->
      locale_paths =
        Enum.map(guides, fn guide ->
          {guide.locale, PublicURLs.docs_path(guide)}
        end)

      entries_for_locale_paths(locale_paths)
    end)
  end

  defp blog_entries do
    published_locales = Enum.filter(Blog.published_locales(), &(&1 in PublicLocales.locales()))

    index_entries =
      published_locales
      |> Enum.map(&{&1, PublicURLs.blog_index_path(&1)})
      |> entries_for_locale_paths()

    post_entries =
      Blog.list_all_posts()
      |> Enum.filter(&(&1.locale in PublicLocales.locales()))
      |> Enum.group_by(& &1.translation_key)
      |> Enum.flat_map(fn {_translation_key, posts} ->
        locale_paths =
          Enum.map(posts, fn post ->
            {post.locale, PublicURLs.blog_post_path(post.locale, post.slug)}
          end)

        entries_for_locale_paths(locale_paths)
      end)

    index_entries ++ post_entries
  end

  defp entries_for_locale_paths(locale_paths) do
    locale_paths = Enum.uniq(locale_paths)
    alternate_links = PublicURLs.alternate_links(locale_paths)

    Enum.map(locale_paths, fn {_locale, path} ->
      %{path: path, alternate_links: alternate_links}
    end)
  end

  defp url_entry(%{path: path, alternate_links: alternate_links}) do
    [
      "  <url>\n",
      "    <loc>",
      path |> absolute_url() |> xml_escape(),
      "</loc>\n",
      Enum.map(alternate_links, &alternate_link/1),
      "  </url>\n"
    ]
  end

  defp alternate_link(%{hreflang: hreflang, href: href}) do
    [
      ~s(    <xhtml:link rel="alternate" hreflang="),
      xml_escape(hreflang),
      ~s(" href="),
      xml_escape(href),
      ~s(" />\n)
    ]
  end

  defp absolute_url(path) do
    StoryarnWeb.Endpoint.url()
    |> URI.merge(path)
    |> URI.to_string()
  end

  @doc false
  @spec xml_escape(term()) :: String.t()
  def xml_escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
