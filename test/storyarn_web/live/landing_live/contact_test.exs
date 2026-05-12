defmodule StoryarnWeb.LandingLive.ContactTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders configured contact page through the public layout", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/contact")

    contact_page = LiveVue.Test.get_vue(view, name: "live/public/contact/Page")
    public_layout = LiveVue.Test.get_vue(view, name: "live/layouts/public/Layout")

    assert contact_page.props["contact-email"] == Application.fetch_env!(:storyarn, :contact_email)
    assert public_layout.props["theme"] == "dark"
    assert html =~ ~s(data-inject="public-layout")
  end
end
