defmodule StoryarnWeb.PublicLocaleTest do
  use StoryarnWeb.ConnCase, async: true

  test "sets the explicit Spanish locale during landing SSR", %{conn: conn} do
    conn = get(conn, "/es")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["es"]
  end

  test "sets the explicit Spanish locale during docs SSR", %{conn: conn} do
    conn = get(conn, "/es/docs/welcome/start-here")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["es"]

    assert LazyHTML.attribute(LazyHTML.query(document, ~s|link[rel="canonical"]|), "href") ==
             [StoryarnWeb.Layouts.absolute_url("/es/docs/welcome/start-here")]
  end

  test "an unprefixed public URL remains English despite a Spanish preference", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{locale: "es"})
      |> get("/")

    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["en"]
  end

  test "auth routes carry their language in the path", %{conn: conn} do
    spanish = conn |> get("/es/users/log-in") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(spanish, "html"), "lang") == ["es"]

    english =
      conn
      |> init_test_session(%{locale: "es"})
      |> get("/users/log-in")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.attribute(LazyHTML.query(english, "html"), "lang") == ["en"]
  end
end
