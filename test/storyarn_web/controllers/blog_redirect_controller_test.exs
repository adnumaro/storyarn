defmodule StoryarnWeb.BlogRedirectControllerTest do
  use StoryarnWeb.ConnCase, async: true

  for path <- [
        "/blog/test-branching-dialogue-before-export",
        "/blog/why-we-are-building-storyarn"
      ] do
    test "permanently redirects #{path} to the launch article", %{conn: conn} do
      conn = get(conn, unquote(path))

      assert redirected_to(conn, :moved_permanently) == "/blog/introducing-storyarn"
    end
  end
end
