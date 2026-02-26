defmodule StoryarnWeb.SceneLive.Components.SceneHeaderTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.SceneHeader

  defp base_assigns(overrides) do
    Map.merge(
      %{
        can_edit: true,
        edit_mode: true,
        workspace: %{slug: "test-ws"},
        project: %{slug: "test-proj"},
        scene: %{
          id: 1,
          name: "Test Scene",
          shortcut: "test-scene",
          width: 2000,
          height: 1500,
          scale_value: nil,
          scale_unit: nil,
          background_asset_id: nil,
          background_asset: nil
        },
        bg_upload_input_id: nil
      },
      overrides
    )
  end

  defp render_actions(overrides \\ %{}) do
    render_component(&SceneHeader.map_actions/1, base_assigns(overrides))
  end

  # =============================================================================
  # map_actions/1 — basic rendering
  # =============================================================================

  describe "map_actions/1 — basic" do
    test "renders play/explore link" do
      html = render_actions()
      assert html =~ "play"
      assert html =~ "explore"
    end

    test "renders export dropdown" do
      html = render_actions()
      assert html =~ "popover-export-map"
      assert html =~ "export_scene"
      assert html =~ "png"
      assert html =~ "svg"
    end
  end

  # =============================================================================
  # map_actions/1 — edit mode / settings
  # =============================================================================

  describe "map_actions/1 — edit/view mode" do
    test "shows edit/view toggle when can_edit" do
      html = render_actions(%{can_edit: true})
      assert html =~ "toggle_edit_mode"
    end

    test "hides edit/view toggle when cannot edit" do
      html = render_actions(%{can_edit: false})
      refute html =~ "toggle_edit_mode"
    end

    test "shows settings popover when can_edit and edit_mode" do
      html = render_actions(%{can_edit: true, edit_mode: true})
      assert html =~ "popover-map-settings"
    end

    test "hides settings popover when not in edit mode" do
      html = render_actions(%{can_edit: true, edit_mode: false})
      refute html =~ "popover-map-settings"
    end

    test "hides settings popover when cannot edit" do
      html = render_actions(%{can_edit: false, edit_mode: true})
      refute html =~ "popover-map-settings"
    end
  end

  # =============================================================================
  # map_actions/1 — background image
  # =============================================================================

  describe "map_actions/1 — background" do
    test "shows upload button when no background and bg_upload_input_id set" do
      html = render_actions(%{bg_upload_input_id: "bg-upload"})
      assert html =~ "Upload Background"
    end

    test "hides upload when no bg_upload_input_id" do
      html = render_actions(%{bg_upload_input_id: nil})
      refute html =~ "Upload Background"
    end

    test "shows background image when set" do
      scene = %{
        id: 1,
        name: "BG Scene",
        shortcut: "bg",
        width: 1000,
        height: 1000,
        scale_value: nil,
        scale_unit: nil,
        background_asset_id: 42,
        background_asset: %{url: "https://example.com/bg.png"}
      }

      html = render_actions(%{scene: scene, bg_upload_input_id: "bg-upload"})
      assert html =~ "https://example.com/bg.png"
      assert html =~ "Change"
      assert html =~ "remove_background"
    end
  end

  # =============================================================================
  # map_actions/1 — scale
  # =============================================================================

  describe "map_actions/1 — scale display" do
    test "shows scale info when both scale_value and scale_unit set" do
      scene = %{
        id: 1,
        name: "Scale Scene",
        shortcut: "sc",
        width: 1000,
        height: 1000,
        scale_value: 500.0,
        scale_unit: "km",
        background_asset_id: nil,
        background_asset: nil
      }

      html = render_actions(%{scene: scene})
      assert html =~ "500"
      assert html =~ "km"
    end

    test "does not show scale text when scale_value is nil" do
      html = render_actions()
      refute html =~ "1 scene width ="
    end

    test "formats whole float as integer" do
      scene = %{
        id: 1,
        name: "S",
        shortcut: "s",
        width: 1000,
        height: 1000,
        scale_value: 5.0,
        scale_unit: "m",
        background_asset_id: nil,
        background_asset: nil
      }

      html = render_actions(%{scene: scene})
      assert html =~ "5 m"
    end

    test "formats float with decimals" do
      scene = %{
        id: 1,
        name: "S",
        shortcut: "s",
        width: 1000,
        height: 1000,
        scale_value: 5.5,
        scale_unit: "m",
        background_asset_id: nil,
        background_asset: nil
      }

      html = render_actions(%{scene: scene})
      assert html =~ "5.5"
    end
  end

  # =============================================================================
  # map_info_bar/1
  # =============================================================================

  describe "map_info_bar/1" do
    defp render_info_bar(overrides \\ %{}) do
      assigns =
        Map.merge(
          %{
            scene: %{id: 1, name: "Test Scene", shortcut: "test-scene"},
            ancestors: [],
            workspace: %{slug: "test-ws"},
            project: %{slug: "test-proj"},
            can_edit: true,
            referencing_flows: []
          },
          overrides
        )

      render_component(&SceneHeader.map_info_bar/1, assigns)
    end

    test "renders scene name" do
      html = render_info_bar()
      assert html =~ "Test Scene"
    end

    test "renders shortcut badge" do
      html = render_info_bar()
      assert html =~ "test-scene"
    end

    test "shows editable title when can_edit" do
      html = render_info_bar(%{can_edit: true})
      assert html =~ "contenteditable"
    end

    test "shows non-editable title when cannot edit" do
      html = render_info_bar(%{can_edit: false})
      refute html =~ "contenteditable"
    end

    test "renders ancestors as breadcrumbs" do
      html =
        render_info_bar(%{
          ancestors: [%{id: 10, name: "Parent Scene"}, %{id: 20, name: "Grandparent"}]
        })

      assert html =~ "Parent Scene"
      assert html =~ "Grandparent"
    end

    test "shows referencing flows count" do
      html =
        render_info_bar(%{
          referencing_flows: [
            %{flow_id: 1, flow_name: "Main Flow"},
            %{flow_id: 2, flow_name: "Side Flow"}
          ]
        })

      assert html =~ "2"
      assert html =~ "Main Flow"
      assert html =~ "Side Flow"
    end

    test "hides referencing flows section when empty" do
      html = render_info_bar(%{referencing_flows: []})
      refute html =~ "popover-referencing-flows"
    end
  end
end
