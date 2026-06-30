defmodule StoryarnWeb.SitemapControllerTest do
  use StoryarnWeb.ConnCase, async: true

  test "GET /sitemap.xml lists public marketing and docs pages", %{conn: conn} do
    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert body =~ "<urlset"
    assert body =~ ~r"<loc>http://localhost:\d+/docs/welcome/what-is-storyarn</loc>"
    assert body =~ ~r"<loc>http://localhost:\d+/docs/narrative-design/flows-overview</loc>"
    assert body =~ ~r"<loc>http://localhost:\d+/contact</loc>"
    refute body =~ "/users/log-in"
    refute body =~ "/projects/invitations"
    refute body =~ "/workspaces/"
  end

  test "GET /robots.txt allows crawlers and points to the sitemap", %{conn: conn} do
    conn = get(conn, ~p"/robots.txt")
    body = response(conn, 200)

    assert body =~ "User-agent: *"
    assert body =~ "Allow: /"
    assert body =~ "Sitemap: https://www.storyarn.com/sitemap.xml"
    refute body =~ "Disallow: /"
  end
end
