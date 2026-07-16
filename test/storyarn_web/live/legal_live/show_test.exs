defmodule StoryarnWeb.LegalLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders privacy page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/privacy")

    legal = LiveVue.Test.get_vue(view, name: "live/public/legal/LegalPage")

    assert legal.props["document"] == "privacy"
    assert legal.props["privacy-url"] == "/privacy"
    assert legal.props["controller-name"] == "Adrián Nuhacet Martin Rodriguez"
    assert legal.props["controller-address"] == "Grådybet 73B, 6700 Esbjerg, Denmark"
    assert html =~ ~s(id="legal-privacy-page")
  end

  test "renders terms page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/terms")

    legal = LiveVue.Test.get_vue(view, name: "live/public/legal/LegalPage")

    assert legal.props["document"] == "terms"
    assert legal.props["controller-name"] == "Adrián Nuhacet Martin Rodriguez"
    assert legal.props["controller-address"] == "Grådybet 73B, 6700 Esbjerg, Denmark"
    assert html =~ ~s(id="legal-terms-page")
  end

  test "keeps Spanish legal navigation and metadata on localized URLs", %{conn: conn} do
    conn = init_test_session(conn, %{locale: "en"})
    {:ok, view, _html} = live(conn, "/es/terms")

    legal = LiveVue.Test.get_vue(view, name: "live/public/legal/LegalPage")
    assert legal.props["privacy-url"] == "/es/privacy"
    assert has_element?(view, ~s|#public-footer a[href="/es/privacy"]|)
    assert has_element?(view, ~s|#public-footer a[href="/es/terms"]|)
    assert has_element?(view, ~s|#public-language-switcher-en[href="/terms"]|)

    metadata = seo_metadata(view)
    assert metadata["locale"] == "es"
    assert URI.parse(metadata["canonical_url"]).path == "/es/terms"
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
