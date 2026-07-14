defmodule StoryarnWeb.BlogLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @path "/blog/test-branching-dialogue-before-export"

  test "renders the complete article as semantic server HTML", %{conn: conn} do
    {:ok, view, html} = live(conn, @path)

    assert has_element?(view, "#blog-post")
    assert has_element?(view, "#blog-post h1")
    assert has_element?(view, "#blog-post-content")

    assert has_element?(
             view,
             ~s|#blog-post-content [id="1-define-the-states-that-control-the-conversation"]|
           )

    assert has_element?(view, ~s|#blog-post-content a[href="/docs/narrative-design/debug-mode"]|)
    assert has_element?(view, ~s|#blog-back-link[href="/blog"]|)

    assert html =~ "A practical pre-export checklist"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s(property="article:published_time" content="2026-07-14")
  end

  test "raises a 404-compatible error for an unknown article", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, "/blog/missing-article")
    end
  end
end
