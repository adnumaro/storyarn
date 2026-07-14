defmodule StoryarnWeb.LandingLive.ContactTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders configured contact page through the public layout", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    contact_page = LiveVue.Test.get_vue(view, name: "live/public/contact/PublicContact")

    assert contact_page.props["contact-email"] == Application.fetch_env!(:storyarn, :contact_email)
    assert has_element?(view, "#public-layout-wrapper.dark")
    assert has_element?(view, "#public-header")
    assert has_element?(view, "#public-footer")

    assert has_element?(
             view,
             ~s|#public-header a[href="/#features-section"][data-phx-link="redirect"]|
           )

    refute html =~ ~s(data-inject="public-layout")
  end
end
