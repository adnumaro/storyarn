defmodule StoryarnWeb.BlogLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @path "/blog/test-branching-dialogue-before-export"

  test "renders the complete article as semantic server HTML", %{conn: conn} do
    {:ok, view, html} = live(conn, @path)
    canonical_url = StoryarnWeb.Layouts.absolute_url(@path)
    document = LazyHTML.from_document(html)

    assert has_element?(view, "#blog-post")
    assert has_element?(view, ~s|#blog-post[lang="en"]|)
    assert has_element?(view, "#blog-post h1")
    assert has_element?(view, "#blog-post-content")

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") == [
             canonical_url
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|meta[property="og:url"]|), "content") == [
             canonical_url
           ]

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
             ~s|#blog-post-content [id="1-define-the-states-that-control-the-conversation"]|
           )

    assert has_element?(view, ~s|#blog-post-content a[href="/docs/narrative-design/debug-mode"]|)
    assert has_element?(view, ~s|#blog-back-link[href="/blog"]|)
    refute has_element?(view, "#blog-back-link[data-phx-link]")

    assert html =~ "A practical pre-export checklist"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s(property="article:published_time" content="2026-07-14")

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

  test "raises a 404-compatible error for an unknown article", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, "/blog/missing-article")
    end
  end
end
