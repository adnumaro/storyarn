defmodule StoryarnWeb.SitemapControllerTest do
  use StoryarnWeb.ConnCase, async: true

  alias StoryarnWeb.SitemapController

  test "GET /sitemap.xml lists canonical localized marketing, blog, and docs pages", %{conn: conn} do
    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    assert body =~ "<urlset"
    assert body =~ ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml")

    assert path_entry(body, "/")
    assert path_entry(body, "/es")
    assert path_entry(body, "/contact")
    assert path_entry(body, "/es/contact")
    assert path_entry(body, "/privacy")
    assert path_entry(body, "/es/privacy")
    assert path_entry(body, "/terms")
    assert path_entry(body, "/es/terms")

    assert path_entry(body, "/docs/welcome/what-is-storyarn")
    assert path_entry(body, "/es/docs/welcome/what-is-storyarn")
    assert path_entry(body, "/docs/narrative-design/flows-overview")
    assert path_entry(body, "/es/docs/narrative-design/flows-overview")

    assert path_entry(body, "/blog")
    assert path_entry(body, "/blog/introducing-storyarn")
    assert path_entry(body, "/es/blog")
    assert path_entry(body, "/es/blog/presentamos-storyarn")

    paths = sitemap_paths(body)
    assert length(paths) == length(Enum.uniq(paths))

    refute "/docs" in paths
    refute "/es/docs" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "/en/"))
    refute "/en" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "/users/"))
    refute Enum.any?(paths, &String.starts_with?(&1, "/projects/"))
    refute Enum.any?(paths, &String.starts_with?(&1, "/workspaces/"))
  end

  test "localized equivalents publish reciprocal hreflang clusters", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    for path <- [
          "/docs/welcome/what-is-storyarn",
          "/es/docs/welcome/what-is-storyarn"
        ] do
      entry = path_entry(body, path)

      assert entry =~
               ~r{<xhtml:link rel="alternate" hreflang="en" href="http://localhost:\d+/docs/welcome/what-is-storyarn" />}

      assert entry =~
               ~r{<xhtml:link rel="alternate" hreflang="es" href="http://localhost:\d+/es/docs/welcome/what-is-storyarn" />}

      assert entry =~
               ~r{<xhtml:link rel="alternate" hreflang="x-default" href="http://localhost:\d+/docs/welcome/what-is-storyarn" />}
    end

    for path <- ["/blog/introducing-storyarn", "/es/blog/presentamos-storyarn"] do
      entry = path_entry(body, path)

      assert entry =~
               ~r{<xhtml:link rel="alternate" hreflang="en" href="http://localhost:\d+/blog/introducing-storyarn" />}

      assert entry =~
               ~r{<xhtml:link rel="alternate" hreflang="es" href="http://localhost:\d+/es/blog/presentamos-storyarn" />}
    end
  end

  test "XML values are escaped before interpolation" do
    assert SitemapController.xml_escape(~s[a&b<c>d"e'f]) ==
             "a&amp;b&lt;c&gt;d&quot;e&apos;f"
  end

  test "GET /robots.txt allows crawlers and points to the sitemap", %{conn: conn} do
    conn = get(conn, ~p"/robots.txt")
    body = response(conn, 200)

    assert body =~ "User-agent: *"
    assert body =~ "Allow: /"
    assert body =~ "Sitemap: https://www.storyarn.com/sitemap.xml"
    refute body =~ "Disallow: /"
  end

  defp sitemap_paths(body) do
    ~r{<loc>([^<]+)</loc>}
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&URI.parse(&1).path)
  end

  defp path_entry(body, path) do
    body
    |> String.split("  <url>\n", trim: true)
    |> Enum.find(fn entry ->
      case Regex.run(~r{<loc>([^<]+)</loc>}, entry, capture: :all_but_first) do
        [url] -> URI.parse(url).path == path
        _other -> false
      end
    end)
  end
end
