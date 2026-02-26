defmodule StoryarnWeb.SceneLive.Components.LayerBarTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.SceneLive.Components.LayerBar

  defp make_layer(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Layer #{id}"),
      visible: Keyword.get(opts, :visible, true),
      fog_enabled: Keyword.get(opts, :fog_enabled, false)
    }
  end

  defp render_bar(layers, opts \\ []) do
    render_component(&LayerBar.layer_bar/1,
      layers: layers,
      active_layer_id: Keyword.get(opts, :active_layer_id, nil),
      renaming_layer_id: Keyword.get(opts, :renaming_layer_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true),
      edit_mode: Keyword.get(opts, :edit_mode, true)
    )
  end

  defp render_panel(layers, opts \\ []) do
    render_component(&LayerBar.layer_panel/1,
      layers: layers,
      active_layer_id: Keyword.get(opts, :active_layer_id, nil),
      renaming_layer_id: Keyword.get(opts, :renaming_layer_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true),
      edit_mode: Keyword.get(opts, :edit_mode, true)
    )
  end

  # ── layer_bar ────────────────────────────────────────────────────

  describe "layer_bar/1" do
    test "renders card chrome with border and shadow" do
      html = render_bar([make_layer(1)])
      assert html =~ "rounded-lg"
      assert html =~ "border"
      assert html =~ "shadow-md"
    end

    test "renders Layers header" do
      html = render_bar([make_layer(1)])
      assert html =~ "Layers"
    end

    test "renders layer names" do
      html = render_bar([make_layer(1, name: "Background"), make_layer(2, name: "Foreground")])
      assert html =~ "Background"
      assert html =~ "Foreground"
    end

    test "shows add layer button when can_edit and edit_mode" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: true)
      assert html =~ "create_layer"
    end

    test "hides add layer button when not in edit mode" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: false)
      refute html =~ "create_layer"
    end

    test "hides add layer button when cannot edit" do
      html = render_bar([make_layer(1)], can_edit: false, edit_mode: true)
      refute html =~ "create_layer"
    end

    test "renders empty bar for no layers" do
      html = render_bar([])
      assert html =~ "Layers"
    end
  end

  # ── layer_panel ──────────────────────────────────────────────────

  describe "layer_panel/1" do
    test "renders without card border wrapper" do
      html = render_panel([make_layer(1)])
      # Panel has no outer card with shadow — the first element is the flex column
      assert html =~ "layer-panel-items"
      refute html =~ "layer-bar-items"
    end

    test "renders New Layer button when can_edit and edit_mode" do
      html = render_panel([make_layer(1)], can_edit: true, edit_mode: true)
      assert html =~ "create_layer"
      assert html =~ "New Layer"
    end

    test "hides New Layer when not in edit_mode" do
      html = render_panel([make_layer(1)], can_edit: true, edit_mode: false)
      refute html =~ "New Layer"
    end

    test "renders layer items" do
      html = render_panel([make_layer(1, name: "Base"), make_layer(2, name: "Top")])
      assert html =~ "Base"
      assert html =~ "Top"
    end
  end

  # ── layer_row (visibility) ──────────────────────────────────────

  describe "layer visibility" do
    test "renders visibility toggle when can_edit in edit_mode" do
      html = render_bar([make_layer(1, visible: true)], can_edit: true, edit_mode: true)
      assert html =~ "toggle_layer_visibility"
    end

    test "shows opacity and line-through when layer is hidden" do
      html = render_bar([make_layer(1, visible: false)], can_edit: true, edit_mode: true)
      assert html =~ "opacity-40"
      assert html =~ "line-through"
    end

    test "hides visibility toggle when cannot edit" do
      html = render_bar([make_layer(1)], can_edit: false, edit_mode: true)
      refute html =~ "toggle_layer_visibility"
    end
  end

  # ── layer_row (active state) ────────────────────────────────────

  describe "layer active state" do
    test "highlights active layer with primary outline" do
      html = render_bar([make_layer(1)], active_layer_id: 1)
      assert html =~ "btn-primary"
      assert html =~ "btn-outline"
    end

    test "uses ghost style for inactive layer" do
      html = render_bar([make_layer(1), make_layer(2)], active_layer_id: 1)
      assert html =~ "btn-ghost"
    end

    test "renders set_active_layer click handler" do
      html = render_bar([make_layer(1)])
      assert html =~ "set_active_layer"
    end
  end

  # ── layer_row (fog indicator) ───────────────────────────────────

  describe "fog of war indicator" do
    test "shows cloud-fog icon when fog_enabled" do
      html = render_bar([make_layer(1, fog_enabled: true)])
      assert html =~ "cloud-fog"
    end

    test "hides fog icon in layer name when not enabled" do
      html = render_bar([make_layer(1, fog_enabled: false)])
      # The fog icon appears in menu toggle always, but NOT in the layer name button
      # The layer button should NOT have the fog indicator span
      refute html =~ ~s(title="Fog of War enabled")
    end
  end

  # ── layer_row (rename) ──────────────────────────────────────────

  describe "layer rename" do
    test "shows input when renaming_layer_id matches" do
      html = render_bar([make_layer(1)], renaming_layer_id: 1, can_edit: true, edit_mode: true)
      assert html =~ "layer-rename-1"
      assert html =~ "rename_layer"
    end

    test "shows name button when not renaming" do
      html = render_bar([make_layer(1, name: "My Layer")], renaming_layer_id: nil)
      assert html =~ "My Layer"
      refute html =~ "layer-rename-"
    end
  end

  # ── layer_row (menu) ───────────────────────────────────────────

  describe "layer menu" do
    test "shows kebab menu when can_edit and edit_mode" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: true)
      assert html =~ "ellipsis-vertical"
    end

    test "hides menu when cannot edit" do
      html = render_bar([make_layer(1)], can_edit: false, edit_mode: true)
      refute html =~ "ellipsis-vertical"
    end

    test "hides menu when not in edit mode" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: false)
      refute html =~ "ellipsis-vertical"
    end

    test "menu has rename option" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: true)
      assert html =~ "start_rename_layer"
      assert html =~ "Rename"
    end

    test "menu has fog toggle option" do
      html = render_bar([make_layer(1, fog_enabled: false)], can_edit: true, edit_mode: true)
      assert html =~ "update_layer_fog"
      assert html =~ "Enable Fog"
    end

    test "fog toggle says Disable when enabled" do
      html = render_bar([make_layer(1, fog_enabled: true)], can_edit: true, edit_mode: true)
      assert html =~ "Disable Fog"
    end

    test "menu has delete option" do
      html = render_bar([make_layer(1), make_layer(2)], can_edit: true, edit_mode: true)
      assert html =~ "set_pending_delete_layer"
    end

    test "delete is disabled when only one layer" do
      html = render_bar([make_layer(1)], can_edit: true, edit_mode: true)
      assert html =~ "disabled"
    end

    test "hides menu during rename" do
      html = render_bar([make_layer(1)], renaming_layer_id: 1, can_edit: true, edit_mode: true)
      refute html =~ "ellipsis-vertical"
    end
  end
end
