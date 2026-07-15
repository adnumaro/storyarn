defmodule StoryarnWeb.LandingLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the public landing", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    landing = LiveVue.Test.get_vue(view, name: "live/public/landing/PublicLanding")

    assert landing.props["is-logged-in"] == false
    assert landing.props["registration-url"] == "/users/register?locale=en"
    assert has_element?(view, "#public-layout-wrapper.dark.min-h-screen")
    assert has_element?(view, "#public-header")
    assert has_element?(view, "#public-footer")
    assert has_element?(view, ~s|#public-header a[href="#features-section"]|)
    assert has_element?(view, ~s|#public-header a[href="/blog"][data-phx-link="redirect"]|)
    assert has_element?(view, "#public-mobile-navigation")
    refute Map.has_key?(landing.props, "waitlist-options")
    refute html =~ ~s(data-inject="public-layout")
  end

  test "exposes public registration through the shared navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s|#public-header a[href="/users/register?locale=en"][data-phx-link="redirect"]|
           )
  end

  test "renders the canonical Spanish public shell from /es", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "en"})
    {:ok, view, _html} = live(conn, "/es")

    assert has_element?(view, ~s|#public-header a[href="/es"]|)
    assert has_element?(view, ~s|#public-header a[href="/es/docs"]|)
    assert has_element?(view, ~s|#public-header a[href="/es/blog"][data-phx-link="redirect"]|)
    assert has_element?(view, ~s|#public-header a[href="/es/contact"]|)
    assert has_element?(view, ~s|#public-mobile-navigation a[href="/es/blog"]|)
    assert has_element?(view, ~s|#public-language-switcher-es[aria-current="page"]|)
    assert has_element?(view, ~s|#public-language-switcher-en[href="/"]|)

    metadata = seo_metadata(view)
    assert metadata["locale"] == "es"
    assert URI.parse(metadata["canonical_url"]).path == "/es"

    assert Enum.map(metadata["alternate_links"], & &1["hreflang"]) == ["en", "es", "x-default"]
  end

  test "the unprefixed landing remains English despite a Spanish preference", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "es"})
    {:ok, view, _html} = live(conn, ~p"/")

    metadata = seo_metadata(view)
    assert metadata["locale"] == "en"
    assert URI.parse(metadata["canonical_url"]).path == "/"
    assert has_element?(view, ~s|#public-language-switcher-en[aria-current="page"]|)
  end

  defp seo_metadata(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#live-seo-metadata")
    |> LazyHTML.attribute("data-metadata")
    |> List.first()
    |> Jason.decode!()
  end
end
