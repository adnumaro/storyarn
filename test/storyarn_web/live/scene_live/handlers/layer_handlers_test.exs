defmodule StoryarnWeb.SceneLive.Handlers.LayerHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.{Repo, Scenes}

  describe "LayerHandlers via SceneLive" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      %{project: project, scene: scene}
    end

    defp show_url(project, scene) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
    end

    # ── Create layer ──────────────────────────────────────────────

    test "create_layer adds a new layer", %{conn: conn, project: project, scene: scene} do
      {:ok, view, _html} = live(conn, show_url(project, scene))

      html = render_click(view, "create_layer")
      assert html =~ "Layer created"
    end

    # ── Set active layer ──────────────────────────────────────────

    test "set_active_layer changes the active layer", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      layer2 = layer_fixture(scene, %{"name" => "Second Layer"})

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "set_active_layer", %{"id" => to_string(layer2.id)})

      # The view should now have layer2 as active
      html = render(view)
      assert html =~ "Second Layer"
    end

    # ── Toggle visibility ─────────────────────────────────────────

    test "toggle_layer_visibility toggles a layer", %{
      conn: conn,
      project: project,
      scene: scene
    } do
      layers = Scenes.list_layers(scene.id)
      layer = hd(layers)

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "toggle_layer_visibility", %{"id" => to_string(layer.id)})

      updated = Scenes.get_layer(scene.id, layer.id)
      refute updated.visible
    end

    # ── Rename layer ──────────────────────────────────────────────

    test "start and complete layer rename", %{conn: conn, project: project, scene: scene} do
      layers = Scenes.list_layers(scene.id)
      layer = hd(layers)

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "start_rename_layer", %{"id" => to_string(layer.id)})

      html =
        render_click(view, "rename_layer", %{
          "id" => to_string(layer.id),
          "value" => "Renamed Layer"
        })

      assert html =~ "renamed" or html =~ "Renamed Layer"

      updated = Scenes.get_layer(scene.id, layer.id)
      assert updated.name == "Renamed Layer"
    end

    test "rename with empty name is a no-op", %{conn: conn, project: project, scene: scene} do
      layers = Scenes.list_layers(scene.id)
      layer = hd(layers)
      original_name = layer.name

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "rename_layer", %{"id" => to_string(layer.id), "value" => ""})

      updated = Scenes.get_layer(scene.id, layer.id)
      assert updated.name == original_name
    end

    # ── Fog of war ────────────────────────────────────────────────

    test "update_layer_fog enables fog", %{conn: conn, project: project, scene: scene} do
      layers = Scenes.list_layers(scene.id)
      layer = hd(layers)

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "update_layer_fog", %{
        "id" => to_string(layer.id),
        "field" => "fog_enabled",
        "value" => "true"
      })

      updated = Scenes.get_layer(scene.id, layer.id)
      assert updated.fog_enabled
    end

    test "update_layer_fog changes fog color", %{conn: conn, project: project, scene: scene} do
      layers = Scenes.list_layers(scene.id)
      layer = hd(layers)

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "update_layer_fog", %{
        "id" => to_string(layer.id),
        "field" => "fog_color",
        "value" => "#ff0000"
      })

      updated = Scenes.get_layer(scene.id, layer.id)
      assert updated.fog_color == "#ff0000"
    end

    # ── Delete layer ──────────────────────────────────────────────

    test "delete_layer removes a layer", %{conn: conn, project: project, scene: scene} do
      _layer2 = layer_fixture(scene, %{"name" => "Extra Layer"})

      {:ok, view, _html} = live(conn, show_url(project, scene))

      layers = Scenes.list_layers(scene.id)
      layer_to_delete = Enum.find(layers, &(&1.name == "Extra Layer"))

      html = render_click(view, "delete_layer", %{"id" => to_string(layer_to_delete.id)})
      assert html =~ "deleted"
    end

    test "delete last layer shows error", %{conn: conn, project: project, scene: scene} do
      layers = Scenes.list_layers(scene.id)
      # Scene starts with 1 default layer
      assert length(layers) == 1
      layer = hd(layers)

      {:ok, view, _html} = live(conn, show_url(project, scene))

      html = render_click(view, "delete_layer", %{"id" => to_string(layer.id)})
      assert html =~ "Cannot delete" or html =~ "last layer"
    end

    # ── Confirm delete layer ──────────────────────────────────────

    test "confirm_delete uses pending layer id", %{conn: conn, project: project, scene: scene} do
      layer2 = layer_fixture(scene, %{"name" => "Pending Delete"})

      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "set_pending_delete_layer", %{"id" => to_string(layer2.id)})
      html = render_click(view, "confirm_delete_layer")

      assert html =~ "deleted"
    end

    # ── Toggle legend ─────────────────────────────────────────────

    test "toggle_legend toggles legend visibility", %{conn: conn, project: project, scene: scene} do
      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "toggle_legend")
      html = render(view)
      # Page renders without crash after toggle
      assert html =~ "scene"
    end

    # ── Toggle pin icon upload ────────────────────────────────────

    test "toggle_pin_icon_upload toggles state", %{conn: conn, project: project, scene: scene} do
      {:ok, view, _html} = live(conn, show_url(project, scene))

      render_click(view, "toggle_pin_icon_upload")
      html = render(view)
      assert html =~ "scene"
    end
  end
end
