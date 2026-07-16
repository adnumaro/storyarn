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

  test "renders Spanish contact at its own canonical URL", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "en"})
    {:ok, view, _html} = live(conn, "/es/contact")

    assert has_element?(view, ~s|#public-header a[href="/es"]|)
    assert has_element?(view, ~s|#public-header a[href="/es/docs"]|)
    assert has_element?(view, ~s|#public-language-switcher-es[aria-current="page"]|)
    assert has_element?(view, ~s|#public-language-switcher-en[href="/contact"]|)

    metadata = seo_metadata(view)
    assert metadata["locale"] == "es"
    assert URI.parse(metadata["canonical_url"]).path == "/es/contact"
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
