defmodule StoryarnWeb.LegalLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders privacy page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/privacy")

    legal = LiveVue.Test.get_vue(view, name: "live/public/legal/LegalPage")

    assert legal.props["document"] == "privacy"
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
end
