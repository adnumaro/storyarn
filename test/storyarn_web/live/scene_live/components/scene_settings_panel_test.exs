defmodule StoryarnWeb.SceneLive.Components.SceneSettingsPanelTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.SceneSettingsPanel

  defp base_scene(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        name: "Test Scene",
        shortcut: "test-scene",
        width: 2000,
        height: 1500,
        scale_value: nil,
        scale_unit: nil,
        background_asset_id: nil,
        background_asset: nil,
        exploration_display_mode: "fit"
      },
      overrides
    )
  end

  defp render_panel(overrides \\ %{}) do
    assigns =
      Map.merge(
        %{scene: base_scene(), can_edit: true, bg_upload_input_id: nil},
        overrides
      )

    render_component(&SceneSettingsPanel.scene_settings_panel/1, assigns)
  end

  # =============================================================================
  # Basic rendering
  # =============================================================================

  describe "scene_settings_panel/1 — basic" do
    test "renders panel title and close button" do
      html = render_panel()
      assert html =~ "Scene Settings"
      assert html =~ "panel:close"
    end

    test "renders custom dimensions" do
      html = render_panel(%{scene: base_scene(%{width: 3000, height: 2000})})
      assert html =~ "3000"
      assert html =~ "2000"
    end

    test "renders default 1000px dimensions when nil" do
      html = render_panel(%{scene: base_scene(%{width: nil, height: nil})})
      assert html =~ "1000"
    end
  end

  # =============================================================================
  # Background image
  # =============================================================================

  describe "scene_settings_panel/1 — background" do
    test "shows upload button when no background and bg_upload_input_id set" do
      html = render_panel(%{bg_upload_input_id: "bg-upload"})
      assert html =~ "Upload Background"
      # Should NOT show change/remove when there's no background
      refute html =~ "Change"
      refute html =~ "remove_background"
    end

    test "hides upload button when no bg_upload_input_id" do
      html = render_panel(%{bg_upload_input_id: nil})
      refute html =~ "Upload Background"
    end

    test "shows image preview with change and remove when background is set" do
      scene =
        base_scene(%{
          background_asset_id: 42,
          background_asset: %{url: "https://example.com/bg.png"}
        })

      html = render_panel(%{scene: scene, bg_upload_input_id: "bg-upload"})
      assert html =~ "https://example.com/bg.png"
      assert html =~ "Change"
      assert html =~ "remove_background"
      # Upload button hidden when background already exists
      refute html =~ "Upload Background"
    end

    test "hides change button when background set but no bg_upload_input_id" do
      scene =
        base_scene(%{
          background_asset_id: 42,
          background_asset: %{url: "https://example.com/bg.png"}
        })

      html = render_panel(%{scene: scene, bg_upload_input_id: nil})
      assert html =~ "https://example.com/bg.png"
      refute html =~ "Change"
      # Remove is always available when background exists
      assert html =~ "remove_background"
    end
  end

  # =============================================================================
  # Scale
  # =============================================================================

  describe "scene_settings_panel/1 — scale" do
    test "shows scale summary text when both value and unit set" do
      scene = base_scene(%{scale_value: 500.0, scale_unit: "km"})
      html = render_panel(%{scene: scene})
      assert html =~ "1 scene width = 500 km"
    end

    test "hides scale summary text when scale_value is nil" do
      html = render_panel()
      refute html =~ "1 scene width ="
    end

    test "format_scale_value renders whole float without decimals" do
      scene = base_scene(%{scale_value: 5.0, scale_unit: "m"})
      html = render_panel(%{scene: scene})
      assert html =~ "1 scene width = 5 m"
    end

    test "format_scale_value preserves decimal precision" do
      scene = base_scene(%{scale_value: 5.5, scale_unit: "m"})
      html = render_panel(%{scene: scene})
      assert html =~ "1 scene width = 5.5 m"
    end
  end
end
