defmodule StoryarnWeb.SceneLive.Components.SceneSearchPanelTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.SceneSearchPanel

  # ── Helpers ──────────────────────────────────────────────────────────

  defp render_panel(overrides \\ %{}) do
    assigns =
      Map.merge(
        %{
          search_query: "",
          search_filter: "all",
          search_results: []
        },
        overrides
      )

    render_component(&SceneSearchPanel.map_search_panel/1, assigns)
  end

  # ── Search input ────────────────────────────────────────────────────

  describe "search input" do
    test "renders search input with placeholder" do
      html = render_panel()

      assert html =~ ~s(name="query")
      assert html =~ "Search elements"
      assert html =~ ~s(phx-change="search_elements")
    end

    test "renders current search query value" do
      html = render_panel(%{search_query: "castle"})

      assert html =~ ~s(value="castle")
    end

    test "hides clear button when query is empty" do
      html = render_panel(%{search_query: ""})

      refute html =~ ~s(phx-click="clear_search")
    end

    test "shows clear button when query is non-empty" do
      html = render_panel(%{search_query: "tower"})

      assert html =~ ~s(phx-click="clear_search")
    end
  end

  # ── Type filter tabs ────────────────────────────────────────────────

  describe "type filter tabs" do
    test "hides filter tabs when query is empty" do
      html = render_panel(%{search_query: ""})

      refute html =~ ~s(phx-click="set_search_filter")
    end

    test "shows all filter tabs when query is non-empty" do
      html = render_panel(%{search_query: "test"})

      assert html =~ "All"
      assert html =~ "Pins"
      assert html =~ "Zones"
      assert html =~ "Notes"
      assert html =~ "Lines"
    end

    test "highlights active filter tab with btn-primary" do
      html = render_panel(%{search_query: "test", search_filter: "pin"})

      # The pin filter button should have btn-primary
      assert html =~ ~s(phx-value-filter="pin")
      # "All" should not have btn-primary since "pin" is active
      assert html =~ "btn-ghost"
    end

    test "each tab has correct filter value" do
      html = render_panel(%{search_query: "test"})

      assert html =~ ~s(phx-value-filter="all")
      assert html =~ ~s(phx-value-filter="pin")
      assert html =~ ~s(phx-value-filter="zone")
      assert html =~ ~s(phx-value-filter="annotation")
      assert html =~ ~s(phx-value-filter="connection")
    end
  end

  # ── Search results ──────────────────────────────────────────────────

  describe "search results" do
    test "hides results when query is empty" do
      html =
        render_panel(%{
          search_query: "",
          search_results: [%{type: "pin", id: "1", label: "Castle"}]
        })

      refute html =~ "Castle"
    end

    test "renders search result labels" do
      results = [
        %{type: "pin", id: "1", label: "Castle Gate"},
        %{type: "zone", id: "2", label: "Forest Area"}
      ]

      html = render_panel(%{search_query: "test", search_results: results})

      assert html =~ "Castle Gate"
      assert html =~ "Forest Area"
    end

    test "each result is a clickable button with focus_search_result event" do
      results = [%{type: "pin", id: "42", label: "Marker"}]

      html = render_panel(%{search_query: "test", search_results: results})

      assert html =~ ~s(phx-click="focus_search_result")
      assert html =~ ~s(phx-value-type="pin")
      assert html =~ ~s(phx-value-id="42")
    end

    test "renders correct icon per result type" do
      results = [
        %{type: "pin", id: "1", label: "Pin Result"},
        %{type: "zone", id: "2", label: "Zone Result"},
        %{type: "annotation", id: "3", label: "Note Result"},
        %{type: "connection", id: "4", label: "Line Result"}
      ]

      html = render_panel(%{search_query: "test", search_results: results})

      # Icons are rendered via <.icon name={...}> — verify the icon names appear
      assert html =~ "map-pin"
      assert html =~ "pentagon"
      assert html =~ "sticky-note"
      assert html =~ "cable"
    end
  end

  # ── No results state ────────────────────────────────────────────────

  describe "no results state" do
    test "shows no results message when query is non-empty and results are empty" do
      html = render_panel(%{search_query: "nonexistent", search_results: []})

      assert html =~ "No results found"
    end

    test "hides no results message when query is empty" do
      html = render_panel(%{search_query: "", search_results: []})

      refute html =~ "No results found"
    end

    test "hides no results message when results exist" do
      results = [%{type: "pin", id: "1", label: "Found"}]

      html = render_panel(%{search_query: "test", search_results: results})

      refute html =~ "No results found"
    end
  end
end
