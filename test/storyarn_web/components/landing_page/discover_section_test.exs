defmodule StoryarnWeb.Components.LandingPage.DiscoverSectionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.LandingPage.DiscoverSection

  test "renders grouped tabs, text overlays and step markers for discover" do
    html = render_component(&DiscoverSection.discover_section/1, %{})
    document = LazyHTML.from_fragment(html)

    # 3 indicator tabs + 3 text overlay tabs = 6 total data-feature-tab elements
    assert document["[data-feature-tab]"] |> Enum.count() == 6
    # Hidden step markers: 1 slide per feature = 3
    assert document["[data-slide]"] |> Enum.count() == 3

    assert document["[data-feature-tab=\"sheets\"]"] |> Enum.count() == 2
    assert document["[data-feature-tab=\"flows\"]"] |> Enum.count() == 2
    assert document["[data-feature-tab=\"scenes\"]"] |> Enum.count() == 2
  end

  test "marks the first feature and slide as the initial active state" do
    html = render_component(&DiscoverSection.discover_section/1, %{})
    document = LazyHTML.from_fragment(html)

    assert document[
             "[data-feature-shell][data-active-feature=\"sheets\"][data-active-slide=\"sheets-inheritance\"]"
           ]
           |> Enum.count() == 1
  end
end
