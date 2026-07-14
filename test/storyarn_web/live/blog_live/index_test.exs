defmodule StoryarnWeb.BlogLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders a server-side blog index with published articles", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/blog")

    assert has_element?(view, "#blog-index")
    assert has_element?(view, "#blog-posts article")

    assert has_element?(
             view,
             ~s|#blog-posts a[href="/blog/test-branching-dialogue-before-export"]|
           )

    assert html =~ "Better systems for interactive stories"
    assert html =~ "How to Test Branching Dialogue"
    assert html =~ ~s(id="public-mobile-menu")
  end
end
