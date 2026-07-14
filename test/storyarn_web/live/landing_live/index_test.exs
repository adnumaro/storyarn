defmodule StoryarnWeb.LandingLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the public landing", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    landing = LiveVue.Test.get_vue(view, name: "live/public/landing/PublicLanding")

    assert landing.props["is-logged-in"] == false
    assert landing.props["registration-url"] == "/users/register"
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
             ~s|#public-header a[href="/users/register"][data-phx-link="redirect"]|
           )
  end
end
