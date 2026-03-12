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
        }
      },
      overrides
    )
  end

  defp render_actions(overrides \\ %{}) do
    assigns = base_assigns(overrides) |> Map.take([:can_edit, :edit_mode])
    render_component(&SceneHeader.map_actions/1, assigns)
  end

  # =============================================================================
  # map_actions/1 — basic rendering
  # =============================================================================

  describe "map_actions/1 — basic" do
    test "does not render play link (moved to dock)" do
      html = render_actions()
      refute html =~ "explore"
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

    test "shows settings button when can_edit and edit_mode" do
      html = render_actions(%{can_edit: true, edit_mode: true})
      assert html =~ "scene-settings-panel"
    end

    test "hides settings button when not in edit mode" do
      html = render_actions(%{can_edit: true, edit_mode: false})
      refute html =~ "scene-settings-panel"
    end

    test "hides settings button when cannot edit" do
      html = render_actions(%{can_edit: false, edit_mode: true})
      refute html =~ "scene-settings-panel"
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
