defmodule StoryarnWeb.BlogLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @path "/blog/introducing-storyarn"

  test "renders the complete article as semantic server HTML", %{conn: conn} do
    {:ok, view, html} = live(conn, @path)
    canonical_url = StoryarnWeb.Layouts.absolute_url(@path)
    document = LazyHTML.from_document(html)

    assert has_element?(view, "#blog-post")
    assert has_element?(view, ~s|#blog-post[lang="en"]|)
    assert has_element?(view, "#blog-post h1")
    assert has_element?(view, "#blog-post-content")
    assert has_element?(view, "#blog-post-hero")
    assert has_element?(view, "#public-header")
    assert has_element?(view, "#public-footer")

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") == [
             canonical_url
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|meta[property="og:url"]|), "content") == [
             canonical_url
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|meta[property="og:type"]|), "content") == [
             "article"
           ]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|meta[property="article:published_time"]|),
             "content"
           ) == ["2026-07-14"]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|meta[property="article:modified_time"]|),
             "content"
           ) == ["2026-07-14"]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|meta[property="article:author"]|), "content") ==
             []

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|script#seo-structured-data|),
             "type"
           ) == ["application/ld+json"]

    assert has_element?(
             view,
             ~s|#blog-post-content [id="the-problem-is-not-writing-the-line"]|
           )

    assert has_element?(view, "#blog-post-content figure figcaption")

    assert has_element?(
             view,
             ~s|#blog-post-content a[href="/docs/narrative-design/debug-mode"][data-phx-link="redirect"]|
           )

    assert has_element?(view, ~s|#blog-back-link[href="/blog"][data-phx-link="redirect"]|)

    assert has_element?(
             view,
             ~s|#blog-register-cta[href="/users/register?locale=en"][data-phx-link="redirect"]|
           )

    assert has_element?(view, "#blog-post h1", "Introducing Storyarn")
    assert has_element?(view, "#blog-post-content", "Writing the sentence is the smallest part")
    assert has_element?(view, "#blog-post-content", "Notion or World Anvil")
    assert has_element?(view, "#blog-post-content", "Yarn Spinner or Ink")
    refute has_element?(view, "#blog-post-content", "spreadsheet")
    refute has_element?(view, "#blog-post-content", "A practical pre-export checklist")
    refute has_element?(view, "#blog-post-content ol")
    assert has_element?(view, ~s|#public-language-switcher-en[aria-current="page"]|)

    assert has_element?(
             view,
             ~s|#public-language-switcher-es[href="/es/blog/presentamos-storyarn"]|
           )

    structured_data =
      document
      |> LazyHTML.query("#seo-structured-data")
      |> LazyHTML.text()
      |> Jason.decode!()

    assert structured_data["@type"] == "BlogPosting"
    assert structured_data["url"] == canonical_url
    assert structured_data["author"]["@type"] == "Organization"
    assert structured_data["inLanguage"] == "en"
  end

  test "the English article URL overrides a Spanish session", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "es"})

    {:ok, view, html} = live(conn, @path)
    document = LazyHTML.from_document(html)

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["en"]
    assert has_element?(view, "#public-header", "Features")
    assert has_element?(view, "#blog-back-link", "Back to the journal")
    assert has_element?(view, ~s|#blog-post[lang="en"]|)
  end

  test "renders the Spanish translation with localized metadata and navigation", %{conn: conn} do
    path = "/es/blog/presentamos-storyarn"
    conn = init_test_session(conn, %{locale: "en"})

    {:ok, view, html} = live(conn, path)
    document = LazyHTML.from_document(html)
    canonical_url = StoryarnWeb.Layouts.absolute_url(path)

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["es"]
    assert has_element?(view, ~s|#blog-post[lang="es"]|)
    assert has_element?(view, "#blog-post h1", "Presentamos Storyarn")
    assert has_element?(view, "#blog-back-link", "Volver al diario")
    assert has_element?(view, ~s|#blog-back-link[href="/es/blog"]|)
    assert has_element?(view, "#blog-post time", "14 de julio de 2026")
    assert has_element?(view, "#blog-post-content", "Notion o World Anvil")
    assert has_element?(view, "#blog-post-content", "Yarn Spinner o Ink")
    refute has_element?(view, "#blog-post-content", "spreadsheet")
    refute has_element?(view, "#blog-post-content ol")
    assert has_element?(view, ~s|#public-language-switcher-es[aria-current="page"]|)

    assert has_element?(
             view,
             ~s|#public-language-switcher-en[href="/blog/introducing-storyarn"]|
           )

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") == [
             canonical_url
           ]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="en"]|),
             "href"
           ) == [StoryarnWeb.Layouts.absolute_url(@path)]

    assert LazyHTML.attribute(
             LazyHTML.query(document, ~s|link[rel="alternate"][hreflang="es"]|),
             "href"
           ) == [canonical_url]

    structured_data =
      document
      |> LazyHTML.query("#seo-structured-data")
      |> LazyHTML.text()
      |> Jason.decode!()

    assert structured_data["inLanguage"] == "es"
    assert structured_data["url"] == canonical_url
  end

  test "raises a 404-compatible error for an unknown article", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, "/blog/missing-article")
    end
  end

  test "does not fall back to a translation from another URL locale", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, "/es/blog/introducing-storyarn")
    end

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, "/blog/presentamos-storyarn")
    end
  end
end
