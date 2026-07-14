defmodule StoryarnWeb.BlogLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a server-side blog index with published articles", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/blog")
    canonical_url = StoryarnWeb.Layouts.absolute_url(~p"/blog")
    document = LazyHTML.from_document(html)

    assert has_element?(view, "#blog-index")
    assert has_element?(view, "#blog-posts article")

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") == [
             canonical_url
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|meta[property="og:url"]|), "content") == [
             canonical_url
           ]

    assert has_element?(view, "#public-manage-cookies")

    assert has_element?(
             view,
             ~s|#public-manage-cookies[phx-click*="storyarn:open-cookie-settings"]|
           )

    assert has_element?(
             view,
             ~s|#blog-posts a[href="/blog/test-branching-dialogue-before-export"]|
           )

    refute has_element?(view, "#blog-posts a[data-phx-link]")

    assert html =~ "Better systems for interactive stories"
    assert html =~ "How to Test Branching Dialogue"
    assert html =~ ~s(id="public-mobile-menu")
  end

  test "declares English when the public blog falls back from a Spanish session", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "es"})

    {:ok, _view, html} = live(conn, ~p"/blog")

    document = LazyHTML.from_document(html)
    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["en"]
  end
end
