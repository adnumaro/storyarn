defmodule StoryarnWeb.SceneLive.Components.ToolbarWidgetsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.ToolbarWidgets

  # =============================================================================
  # toolbar_opacity_slider/1 — exercises format_opacity/1
  # =============================================================================

  describe "toolbar_opacity_slider/1" do
    test "renders with nil value (default 30%)" do
      html =
        render_component(&ToolbarWidgets.toolbar_opacity_slider/1, %{
          event: "update_opacity",
          element_id: "z1",
          value: nil,
          disabled: false
        })

      assert html =~ "30%"
      assert html =~ "Opacity"
    end

    test "renders with float value" do
      html =
        render_component(&ToolbarWidgets.toolbar_opacity_slider/1, %{
          event: "update_opacity",
          element_id: "z1",
          value: 0.5,
          disabled: false
        })

      assert html =~ "50%"
    end

    test "renders with full opacity" do
      html =
        render_component(&ToolbarWidgets.toolbar_opacity_slider/1, %{
          event: "update_opacity",
          element_id: "z1",
          value: 1.0,
          disabled: false
        })

      assert html =~ "100%"
    end

    test "renders with zero opacity" do
      html =
        render_component(&ToolbarWidgets.toolbar_opacity_slider/1, %{
          event: "update_opacity",
          element_id: "z1",
          value: 0.0,
          disabled: false
        })

      assert html =~ "0%"
    end
  end

  # =============================================================================
  # toolbar_stroke_picker/1 — exercises border_dash/1
  # =============================================================================

  describe "toolbar_stroke_picker/1" do
    defp stroke_assigns(overrides \\ %{}) do
      Map.merge(
        %{
          id: "stroke-1",
          event: "update_style",
          element_id: "z1",
          current_style: "solid",
          current_color: "#FF0000",
          current_width: 2,
          style_field: "border_style",
          color_field: "border_color",
          width_field: "border_width",
          label: "Border",
          disabled: false
        },
        overrides
      )
    end

    test "renders with solid style" do
      html = render_component(&ToolbarWidgets.toolbar_stroke_picker/1, stroke_assigns())
      # solid → border_dash returns "none"
      assert html =~ "stroke-dasharray"
    end

    test "renders with dashed style" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_stroke_picker/1,
          stroke_assigns(%{current_style: "dashed"})
        )

      assert html =~ "6,3"
    end

    test "renders with dotted style" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_stroke_picker/1,
          stroke_assigns(%{current_style: "dotted"})
        )

      assert html =~ "2,2"
    end

    test "renders with unknown style (defaults to none)" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_stroke_picker/1,
          stroke_assigns(%{current_style: "wavy"})
        )

      # unknown → "none"
      assert html =~ "none"
    end
  end

  # =============================================================================
  # toolbar_color_picker/1
  # =============================================================================

  describe "toolbar_color_picker/1" do
    test "renders color swatch with current value" do
      html =
        render_component(&ToolbarWidgets.toolbar_color_picker/1, %{
          id: "fill-1",
          event: "update_fill",
          element_id: "z1",
          field: "fill_color",
          value: "#ef4444",
          label: "Fill Color",
          disabled: false
        })

      assert html =~ "#ef4444"
      assert html =~ "Fill Color"
    end
  end

  # =============================================================================
  # toolbar_target_picker/1 — exercises target_type helpers
  # =============================================================================

  describe "toolbar_target_picker/1" do
    defp target_assigns(overrides \\ %{}) do
      Map.merge(
        %{
          id: "target-1",
          event: "update_target",
          element_id: "p1",
          current_type: nil,
          current_target_id: nil,
          project_scenes: [],
          project_sheets: [],
          project_flows: [],
          disabled: false
        },
        overrides
      )
    end

    test "renders with no link" do
      html = render_component(&ToolbarWidgets.toolbar_target_picker/1, target_assigns())
      assert html =~ "No link"
    end

    test "renders with scene target" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_target_picker/1,
          target_assigns(%{
            current_type: "scene",
            current_target_id: 1,
            project_scenes: [%{id: 1, name: "Tavern"}]
          })
        )

      assert html =~ "Tavern"
    end

    test "renders with sheet target" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_target_picker/1,
          target_assigns(%{
            current_type: "sheet",
            current_target_id: 2,
            project_sheets: [%{id: 2, name: "Hero Sheet", children: []}]
          })
        )

      assert html =~ "Hero Sheet"
    end

    test "renders with flow target" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_target_picker/1,
          target_assigns(%{
            current_type: "flow",
            current_target_id: 3,
            project_flows: [%{id: 3, name: "Main Flow"}]
          })
        )

      assert html =~ "Main Flow"
    end

    test "shows type label when target not found" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_target_picker/1,
          target_assigns(%{
            current_type: "scene",
            current_target_id: 999,
            project_scenes: []
          })
        )

      assert html =~ "Scene"
    end

    test "flattens nested sheets" do
      html =
        render_component(
          &ToolbarWidgets.toolbar_target_picker/1,
          target_assigns(%{
            current_type: "sheet",
            current_target_id: 5,
            project_sheets: [
              %{
                id: 1,
                name: "Parent",
                children: [%{id: 5, name: "Nested Child", children: []}]
              }
            ]
          })
        )

      assert html =~ "Nested Child"
    end
  end

  # =============================================================================
  # toolbar_size_picker/1
  # =============================================================================

  describe "toolbar_size_picker/1" do
    test "renders with default options" do
      html =
        render_component(&ToolbarWidgets.toolbar_size_picker/1, %{
          event: "update_size",
          element_id: "p1",
          field: "size",
          current: "md",
          options: [{"sm", "S"}, {"md", "M"}, {"lg", "L"}],
          disabled: false
        })

      assert html =~ "S"
      assert html =~ "M"
      assert html =~ "L"
      assert html =~ "toolbar-btn-active"
    end
  end

  # =============================================================================
  # toolbar_layer_picker/1
  # =============================================================================

  describe "toolbar_layer_picker/1" do
    test "renders with layers" do
      html =
        render_component(&ToolbarWidgets.toolbar_layer_picker/1, %{
          id: "layer-1",
          event: "move_to_layer",
          element_id: "z1",
          current_layer_id: 1,
          layers: [%{id: 1, name: "Default Layer"}, %{id: 2, name: "Background"}],
          disabled: false
        })

      assert html =~ "Default Layer"
      assert html =~ "Background"
    end

    test "renders with empty layers" do
      html =
        render_component(&ToolbarWidgets.toolbar_layer_picker/1, %{
          id: "layer-1",
          event: "move_to_layer",
          element_id: "z1",
          current_layer_id: nil,
          layers: [],
          disabled: false
        })

      assert html =~ "popover-layer-layer-1"
    end
  end
end
