defmodule StoryarnWeb.LandingLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the public landing", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    landing = LiveVue.Test.get_vue(view, name: "live/public/landing/PublicLanding")

    assert landing.props["is-logged-in"] == false
    assert landing.props["registration-url"] == "/users/register"
    assert has_element?(view, "#public-layout-wrapper.dark.min-h-screen")
    refute Map.has_key?(landing.props, "waitlist-options")
    assert html =~ ~s(data-inject="public-layout")
  end

  test "exposes public registration through the shared navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    public_layout = LiveVue.Test.get_vue(view, name: "live/layouts/public/Layout")

    assert public_layout.props["urls"]["register"] == "/users/register"
  end
end
