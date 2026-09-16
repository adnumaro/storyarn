defmodule StoryarnWeb.PublicSEOLinksTest do
  use StoryarnWeb.ConnCase, async: true

  test "every sitemap and llms link resolves to a current canonical, indexable page" do
    sitemap = build_conn() |> get("/sitemap.xml") |> response(200)
    llms = build_conn() |> get("/llms.txt") |> response(200)

    locations = captures(~r{<loc>([^<]+)</loc>}, sitemap)
    alternates = captures(~r{<xhtml:link[^>]+href="([^"]+)"}, sitemap)
    llms_urls = captures(~r{\]\((https?://[^)]+)\)}, llms)
    sitemap_url = StoryarnWeb.Endpoint.url() <> "/sitemap.xml"

    assert locations != []
    assert alternates |> MapSet.new() |> MapSet.subset?(MapSet.new(locations))
    assert MapSet.new(llms_urls -- [sitemap_url]) == MapSet.new(locations)

    Enum.each(locations, fn url ->
      assert String.starts_with?(url, StoryarnWeb.Endpoint.url() <> "/")
      conn = get(build_conn(), URI.parse(url).path)
      assert conn.status == 200, "SEO URL #{url} returned #{conn.status}"

      document = LazyHTML.from_document(conn.resp_body)

      assert LazyHTML.attribute(LazyHTML.query(document, "link[rel=canonical]"), "href") == [url],
             "SEO URL #{url} does not declare itself canonical"

      assert LazyHTML.attribute(LazyHTML.query(document, "meta[property='og:url']"), "content") == [url]

      robots =
        LazyHTML.attribute(LazyHTML.query(document, "meta[name=robots]"), "content") ++
          get_resp_header(conn, "x-robots-tag")

      refute Enum.any?(robots, &String.contains?(&1, "noindex")),
             "SEO URL #{url} is marked noindex"

      page_alternates = LazyHTML.attribute(LazyHTML.query(document, "link[hreflang]"), "href")

      assert Enum.all?(page_alternates, &(&1 in locations)),
             "SEO URL #{url} links to an alternate missing from the sitemap"

      if String.contains?(URI.parse(url).path, "/docs/") do
        assert document |> LazyHTML.query("#docs-reading-title") |> LazyHTML.text() |> String.trim() != "",
               "Documentation URL #{url} has no heading in the initial HTML"

        assert document |> LazyHTML.query("#docs-reading-body p") |> Enum.any?(),
               "Documentation URL #{url} has no article paragraphs in the initial HTML"

        assert document |> LazyHTML.query("#docs-reading-navigation a[href]") |> Enum.any?(),
               "Documentation URL #{url} has no crawlable navigation in the initial HTML"
      end
    end)
  end

  defp captures(pattern, body) do
    pattern |> Regex.scan(body, capture: :all_but_first) |> List.flatten() |> Enum.uniq()
  end
end
