defmodule StoryarnWeb.BlogLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a server-side blog index with published articles", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/blog")
    canonical_url = StoryarnWeb.Layouts.absolute_url(~p"/blog")
    document = LazyHTML.from_document(html)

    assert has_element?(view, "#blog-index")
    assert has_element?(view, ~s|#blog-index[lang="en"]|)
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
             ~s|#blog-featured-post a[href="/blog/version-control-branching-narratives"][data-phx-link="redirect"]|
           )

    assert has_element?(
             view,
             ~s|#blog-featured-post img[src="/images/blog/version-control-branching-narratives.svg"][fetchpriority="high"]|
           )

    assert has_element?(
             view,
             ~s|#blog-posts a[href="/blog/introducing-storyarn"][data-phx-link="redirect"]|
           )

    assert has_element?(view, ~s|#public-header a[href="/#features-section"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/docs"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/blog"][data-phx-link]|)
    assert has_element?(view, ~s|#public-header a[href="/contact"][data-phx-link]|)

    assert has_element?(view, "#blog-index h1", "Notes on building a connected narrative design platform")
    assert has_element?(view, "#blog-featured-post h2", "Going Back Without Breaking the Story")
    assert has_element?(view, ~s|#public-language-switcher-en[aria-current="page"]|)
    assert has_element?(view, ~s|#public-language-switcher-es[href="/es/blog"]|)

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="en"]|),
             "href"
           ) == [StoryarnWeb.Layouts.absolute_url("/blog")]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="es"]|),
             "href"
           ) == [StoryarnWeb.Layouts.absolute_url("/es/blog")]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="x-default"]|),
             "href"
           ) == [StoryarnWeb.Layouts.absolute_url("/blog")]

    assert has_element?(
             view,
             ~s|#public-mobile-menu-button[aria-expanded="false"][phx-click*="push_focus"][phx-click*="flash-group"]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-navigation[role="dialog"][aria-modal="true"][aria-hidden="true"][phx-hook="PublicMobileNavigation"][data-close*="pop_focus"][data-close*="overflow-hidden"]|
           )

    refute has_element?(view, "#public-mobile-navigation[phx-window-keydown]")

    assert has_element?(
             view,
             ~s|#public-mobile-navigation-focus-wrap[phx-hook="Phoenix.FocusWrap"]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-menu-close[phx-click*="pop_focus"][phx-click*="flash-group"]|
           )

    assert has_element?(
             view,
             ~s|#public-mobile-language-switcher-es[phx-click*="pop_focus"][phx-click*="overflow-hidden"]|
           )
  end

  test "the unprefixed blog URL is fully English regardless of the session", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "es"})

    {:ok, view, html} = live(conn, ~p"/blog")

    document = LazyHTML.from_document(html)
    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["en"]
    assert has_element?(view, "#public-header", "Features")
    assert has_element?(view, "#public-header", "Create account")
    assert has_element?(view, "#blog-index h1", "Notes on building a connected")
    assert has_element?(view, ~s|#blog-featured-post[lang="en"]|)
    assert has_element?(view, "#blog-featured-post h2", "Going Back Without Breaking the Story")
  end

  test "renders the localized Spanish index from its canonical URL", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "en"})

    {:ok, view, html} = live(conn, "/es/blog")
    document = LazyHTML.from_document(html)

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["es"]
    assert has_element?(view, ~s|#blog-index[lang="es"]|)
    assert has_element?(view, "#public-header", "Características")
    assert has_element?(view, ~s|#public-header a[href="/es/blog"]|)
    assert has_element?(view, "#blog-index h1", "Notas sobre cómo construimos")
    assert has_element?(view, "#blog-featured-post h2", "Volver atrás sin romper la historia")

    assert has_element?(
             view,
             ~s|#blog-featured-post a[href="/es/blog/control-versiones-narrativa-ramificada"]|
           )

    assert has_element?(view, "#blog-featured-post time", "17 de julio de 2026")
    assert has_element?(view, ~s|#blog-posts a[href="/es/blog/presentamos-storyarn"]|)
    assert has_element?(view, ~s|#public-language-switcher-es[aria-current="page"]|)
    assert has_element?(view, ~s|#public-language-switcher-en[href="/blog"]|)

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") == [
             StoryarnWeb.Layouts.absolute_url("/es/blog")
           ]
  end
end
