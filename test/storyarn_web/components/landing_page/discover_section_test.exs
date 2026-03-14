defmodule StoryarnWeb.Components.LandingPage.DiscoverSectionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.LandingPage.DiscoverSection

  test "renders grouped tabs, previews and slides for discover" do
    html = render_component(&DiscoverSection.discover_section/1, %{})
    document = LazyHTML.from_fragment(html)

    assert document["[data-feature-tab]"] |> Enum.count() == 4
    assert document["[data-feature-preview]"] |> Enum.count() == 10
    assert document["[data-slide]"] |> Enum.count() == 10

    assert document["[data-feature-tab=\"dashboard\"]"] |> Enum.count() == 1
    assert document["[data-feature-tab=\"sheets\"]"] |> Enum.count() == 1
    assert document["[data-feature-tab=\"flows\"]"] |> Enum.count() == 1
    assert document["[data-feature-tab=\"scenes\"]"] |> Enum.count() == 1
  end

  test "marks the first feature and slide as the initial active state" do
    html = render_component(&DiscoverSection.discover_section/1, %{})
    document = LazyHTML.from_fragment(html)

    assert document[
             "[data-feature-shell][data-active-feature=\"dashboard\"][data-active-slide=\"dashboard-overview\"]"
           ]
           |> Enum.count() == 1

    assert document["[data-feature-group=\"dashboard\"].is-active"] |> Enum.count() == 1
    assert document["[data-slide-preview=\"dashboard-overview\"].is-active"] |> Enum.count() == 1

    assert document["[data-feature-triggers=\"dashboard\"][data-slide-count=\"1\"]"]
           |> Enum.count() == 1
  end
end
