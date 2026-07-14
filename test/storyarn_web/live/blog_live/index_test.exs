defmodule StoryarnWeb.BlogLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a server-side blog index with published articles", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/blog")
    canonical_url = StoryarnWeb.Layouts.absolute_url(~p"/blog")
    document = LazyHTML.from_document(html)

    assert has_element?(view, "#blog-index")
    assert has_element?(view, ~s|#blog-featured-post[lang="en"]|)
    assert has_element?(view, "#public-header")
    assert has_element?(view, "#public-footer")

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
             ~s|#blog-featured-post a[href="/blog/introducing-storyarn"][data-phx-link="redirect"]|
           )

    assert has_element?(
             view,
             ~s|#blog-featured-post img[src="/images/docs/project-dashboard-current.png"][fetchpriority="high"]|
           )

    assert has_element?(view, ~s|#public-header a[href="/#features-section"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/docs"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/blog"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/contact"][data-phx-link]|)

    assert has_element?(view, "#blog-index h1", "Notes on building a connected narrative design platform")
    assert has_element?(view, "#blog-featured-post h2", "Introducing Storyarn")

    assert has_element?(
             view,
             ~s|#public-mobile-menu-button[aria-expanded="false"][phx-click*="push_focus"][phx-click*="flash-group"]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-navigation[role="dialog"][aria-modal="true"][aria-hidden="true"][phx-window-keydown]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-navigation-focus-wrap[phx-hook="Phoenix.FocusWrap"]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-menu-close[phx-click*="pop_focus"][phx-click*="flash-group"]|
           )
  end

  test "keeps the Spanish public shell while marking English editorial content", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "es"})

    {:ok, view, html} = live(conn, ~p"/blog")

    document = LazyHTML.from_document(html)
    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["es"]
    assert has_element?(view, "#public-header", "Características")
    assert has_element?(view, "#public-header", "Crear cuenta")
    assert has_element?(view, "#blog-index h1", "Notas sobre cómo construimos")
    assert has_element?(view, ~s|#blog-featured-post[lang="en"]|)
  end
end
