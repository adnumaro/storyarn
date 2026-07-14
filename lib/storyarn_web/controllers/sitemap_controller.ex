defmodule StoryarnWeb.SitemapController do
  use StoryarnWeb, :controller

  alias Storyarn.Blog
  alias Storyarn.Docs

  @static_paths [
    "/",
    "/contact",
    "/blog",
    "/docs",
    "/privacy",
    "/terms"
  ]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, sitemap_xml())
  end

  defp sitemap_xml do
    urls =
      (@static_paths ++ blog_paths() ++ docs_paths())
      |> Enum.uniq()
      |> Enum.map(&url_entry/1)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      urls,
      ~s(</urlset>\n)
    ]
  end

  defp docs_paths do
    "en"
    |> Docs.list_guides()
    |> Enum.map(&"/docs/#{&1.url_path}")
  end

  defp blog_paths do
    "en"
    |> Blog.list_posts()
    |> Enum.map(&"/blog/#{&1.slug}")
  end

  defp url_entry(path) do
    [
      "  <url>\n",
      "    <loc>",
      path |> absolute_url() |> xml_escape(),
      "</loc>\n",
      "  </url>\n"
    ]
  end

  defp absolute_url(path) do
    StoryarnWeb.Endpoint.url()
    |> URI.merge(path)
    |> URI.to_string()
  end

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
