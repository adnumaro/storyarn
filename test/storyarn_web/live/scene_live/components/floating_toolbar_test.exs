defmodule StoryarnWeb.SceneLive.Components.FloatingToolbarTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.FloatingToolbar

  defp base_assigns(type, element, overrides \\ %{}) do
    Map.merge(
      %{
        selected_type: type,
        selected_element: element,
        layers: [%{id: 1, name: "Default Layer"}],
        can_edit: true,
        can_toggle_lock: true,
        project_scenes: [],
        project_sheets: [],
        project_flows: [],
        project_variables: [],
        panel_sections: %{}
      },
      overrides
    )
  end

  defp zone_element(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        name: "Test Zone",
        fill_color: "#ef4444",
        opacity: 0.3,
        border_style: "solid",
        border_color: "#000000",
        border_width: 2,
        locked: false,
        layer_id: 1,
        action_type: "none",
        action_data: %{},
        condition: nil,
        condition_effect: "visibility",
        tooltip: "",
        target_type: nil,
        target_id: nil
      },
      overrides
    )
  end

  defp pin_element(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        label: "Test Pin",
        pin_type: "location",
        size: "md",
        color: "#3b82f6",
        opacity: 1.0,
        locked: false,
        layer_id: 1,
        action_type: "none",
        action_data: %{},
        condition: nil,
        condition_effect: "visibility",
        target_type: nil,
        target_id: nil,
        tooltip: ""
      },
      overrides
    )
  end

  defp connection_element(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        label: "",
        show_label: false,
        bidirectional: false,
        color: "#6b7280",
        line_width: 2,
        line_style: "solid",
        waypoints: []
      },
      overrides
    )
  end

  defp annotation_element(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        color: "#fbbf24",
        font_size: "md",
        locked: false,
        layer_id: 1
      },
      overrides
    )
  end

  # =============================================================================
  # Zone toolbar
  # =============================================================================

  describe "floating_toolbar/1 — zone" do
    test "renders zone toolbar" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element())
        )

      assert html =~ "floating-toolbar"
    end

    test "zone with action_type instruction shows instruction builder" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element(%{action_type: "instruction"}))
        )

      assert html =~ "zap"
    end

    test "zone with action_type display shows display icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element(%{action_type: "display"}))
        )

      assert html =~ "bar-chart-3"
    end

    test "zone with action_type none shows none icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element(%{action_type: "none"}))
        )

      assert html =~ "circle-off"
    end

    test "zone renders lock toggle when can_toggle_lock" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element())
        )

      assert html =~ "unlock"
    end

    test "zone shows lock icon when locked" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element(%{locked: true}))
        )

      assert html =~ "lock"
    end
  end

  # =============================================================================
  # Pin toolbar
  # =============================================================================

  describe "floating_toolbar/1 — pin" do
    test "renders pin toolbar" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element())
        )

      assert html =~ "floating-toolbar"
    end

    test "pin with location type shows map-pin icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element(%{pin_type: "location"}))
        )

      assert html =~ "map-pin"
    end

    test "pin with character type shows user icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element(%{pin_type: "character"}))
        )

      assert html =~ "user"
    end

    test "pin with event type shows zap icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element(%{pin_type: "event"}))
        )

      # zap is used both for event pin type and instruction action type
      assert html =~ "zap"
    end

    test "pin with custom type shows star icon" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element(%{pin_type: "custom"}))
        )

      assert html =~ "star"
    end

    test "pin with unknown type falls back to map-pin" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("pin", pin_element(%{pin_type: "unknown"}))
        )

      assert html =~ "map-pin"
    end
  end

  # =============================================================================
  # Connection toolbar
  # =============================================================================

  describe "floating_toolbar/1 — connection" do
    test "renders connection toolbar" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("connection", connection_element())
        )

      assert html =~ "floating-toolbar"
    end

    test "connection with waypoints shows straighten button" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("connection", connection_element(%{waypoints: [%{"x" => 1, "y" => 2}]}))
        )

      assert html =~ "Straighten path"
    end

    test "connection with bidirectional true shows active state" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("connection", connection_element(%{bidirectional: true}))
        )

      assert html =~ "toolbar-btn-active"
    end

    test "connection with show_label true shows active state" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("connection", connection_element(%{show_label: true}))
        )

      assert html =~ "toolbar-btn-active"
    end
  end

  # =============================================================================
  # Annotation toolbar
  # =============================================================================

  describe "floating_toolbar/1 — annotation" do
    test "renders annotation toolbar" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("annotation", annotation_element())
        )

      assert html =~ "floating-toolbar"
    end
  end

  # =============================================================================
  # Disabled state
  # =============================================================================

  describe "floating_toolbar/1 — disabled" do
    test "disables buttons when can_edit is false" do
      html =
        render_component(
          &FloatingToolbar.floating_toolbar/1,
          base_assigns("zone", zone_element(), %{can_edit: false})
        )

      assert html =~ "disabled"
    end
  end
end
