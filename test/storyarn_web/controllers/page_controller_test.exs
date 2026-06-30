defmodule StoryarnWeb.PageControllerTest do
  use StoryarnWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Narrative Design Platform"
    assert html_response(conn, 200) =~ ~s(<meta name="description")
    assert html_response(conn, 200) =~ ~s(<link rel="canonical")
    assert html_response(conn, 200) =~ "video game design platform"
    assert html_response(conn, 200) =~ "game design platform"
    assert html_response(conn, 200) =~ "Yarn Spinner"
  end
end
