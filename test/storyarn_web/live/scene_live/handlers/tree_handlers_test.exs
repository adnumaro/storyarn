defmodule StoryarnWeb.SceneLive.Handlers.TreeHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

  defp scene_url(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp scenes_index_url(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
  end

  # ── handle_create_scene ───────────────────────────────────────────

  describe "create_scene event" do
    setup :register_and_log_in_user

    test "creates a new scene and navigates to it", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Existing Scene"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_scene", %{})

      {path, _flash} = assert_redirect(view)
      # Path should be to a scene page (has /scenes/ followed by an ID)
      assert path =~ "/scenes/"
      # Ensure it's not the same scene
      refute path =~ "/scenes/#{scene.id}"
    end

    test "rejected for viewer role", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html = render_click(view, "create_scene", %{})
      # Viewer should not be able to create — flash or unchanged page
      assert html =~ "scene-canvas"
    end
  end

  # ── handle_create_child_scene ─────────────────────────────────────

  describe "create_child_scene event" do
    setup :register_and_log_in_user

    test "creates a child scene under given parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent_scene = scene_fixture(project, %{name: "Parent"})

      {:ok, view, _html} = live(conn, scene_url(project, parent_scene))

      render_click(view, "create_child_scene", %{"parent-id" => parent_scene.id})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"
      refute path =~ "/scenes/#{parent_scene.id}"
    end
  end

  # ── handle_set_pending_delete_scene ───────────────────────────────

  describe "set_pending_delete_scene event" do
    setup :register_and_log_in_user

    test "sets pending_delete_id assign", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      other_scene = scene_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # This event doesn't have authorization wrapper, anyone can set it
      html = render_click(view, "set_pending_delete_scene", %{"id" => to_string(other_scene.id)})

      # Should not crash and scene should still be rendered
      assert html =~ "scene-canvas"
    end
  end

  # ── handle_confirm_delete_scene ───────────────────────────────────

  describe "confirm_delete_scene event" do
    setup :register_and_log_in_user

    test "deletes the scene set in pending_delete_id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Current"})
      to_delete = scene_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # First set pending delete
      render_click(view, "set_pending_delete_scene", %{"id" => to_string(to_delete.id)})

      # Then confirm deletion
      render_click(view, "confirm_delete_scene", %{})

      # The scene should be soft-deleted
      deleted = Scenes.get_scene(project.id, to_delete.id)
      assert is_nil(deleted) || deleted.deleted_at != nil
    end

    test "does nothing when no pending_delete_id is set", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # Confirm without setting pending — should be a no-op
      html = render_click(view, "confirm_delete_scene", %{})
      assert html =~ "scene-canvas"
    end
  end

  # ── handle_delete_scene ───────────────────────────────────────────

  describe "delete_scene event" do
    setup :register_and_log_in_user

    test "deletes a different scene and stays on current", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Current"})
      other = scene_fixture(project, %{name: "Other"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "delete_scene", %{"id" => to_string(other.id)})

      # Should stay on current page (not redirect) — the scenes tree reloads
      html = render(view)
      assert html =~ "scene-canvas"

      # Verify other scene was soft-deleted
      deleted = Scenes.get_scene(project.id, other.id)
      assert is_nil(deleted)
    end

    test "deletes the currently viewed scene and redirects to index", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Current"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "delete_scene", %{"id" => to_string(scene.id)})

      {path, _flash} = assert_redirect(view)
      assert path == scenes_index_url(project)
    end

    test "handles non-existent scene id gracefully", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html = render_click(view, "delete_scene", %{"id" => "999999"})
      # Should not crash — just no-op
      assert html =~ "scene-canvas"
    end

    test "rejected for viewer role", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)
      target = scene_fixture(project, %{name: "Target"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "delete_scene", %{"id" => to_string(target.id)})

      # Scene should not be deleted
      assert Scenes.get_scene(project.id, target.id) != nil
    end
  end

  # ── handle_move_to_parent ─────────────────────────────────────────

  describe "move_to_parent event" do
    setup :register_and_log_in_user

    test "moves scene to new parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Current"})
      child = scene_fixture(project, %{name: "Child"})
      new_parent = scene_fixture(project, %{name: "New Parent"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html =
        render_click(view, "move_to_parent", %{
          "item_id" => to_string(child.id),
          "new_parent_id" => to_string(new_parent.id),
          "position" => "0"
        })

      assert html =~ "scene-canvas"

      # Verify scene was moved
      moved = Scenes.get_scene(project.id, child.id)
      assert moved.parent_id == new_parent.id
    end

    test "moves scene to root (nil parent)", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = scene_fixture(project, %{name: "Parent"})

      child =
        scene_fixture(project, %{name: "Child"})

      # First move child under parent
      {:ok, _} = Scenes.move_scene_to_position(child, parent.id, 0)

      {:ok, view, _html} = live(conn, scene_url(project, parent))

      html =
        render_click(view, "move_to_parent", %{
          "item_id" => to_string(child.id),
          "new_parent_id" => "",
          "position" => "0"
        })

      assert html =~ "scene-canvas"

      moved = Scenes.get_scene(project.id, child.id)
      assert is_nil(moved.parent_id)
    end

    test "handles non-existent scene id gracefully", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html =
        render_click(view, "move_to_parent", %{
          "item_id" => "999999",
          "new_parent_id" => "",
          "position" => "0"
        })

      # Should not crash — just no-op
      assert html =~ "scene-canvas"
    end

    test "shows error when moving scene into its own descendant (cyclic)",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child"})

      # Move child under parent first
      {:ok, _} = Scenes.move_scene_to_position(child, parent.id, 0)

      {:ok, view, _html} = live(conn, scene_url(project, parent))

      # Try to move parent under its own child — cyclic error
      html =
        render_click(view, "move_to_parent", %{
          "item_id" => to_string(parent.id),
          "new_parent_id" => to_string(child.id),
          "position" => "0"
        })

      assert html =~ "Could not move scene"
    end
  end

  # ── handle_navigate_to_target ─────────────────────────────────────

  describe "navigate_to_target event" do
    setup :register_and_log_in_user

    test "navigates to existing target scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Source"})
      target = scene_fixture(project, %{name: "Target"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => target.id})

      assert_redirect(view, scene_url(project, target))
    end

    test "shows flash when target scene is deleted", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # Navigate to a non-existent scene id
      html = render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => 999_999})

      assert html =~ "no longer exists"
    end

    test "clears stale zone reference when target scene is deleted", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      # Create a child scene and zone pointing to it
      child = scene_fixture(project, %{name: "Child"})

      zone =
        zone_fixture(scene, %{
          "name" => "Linked Zone",
          "target_type" => "scene",
          "target_id" => child.id
        })

      # Delete the child scene so the zone link becomes stale
      Scenes.delete_scene(child)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html =
        render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => child.id})

      assert html =~ "no longer exists"

      # Verify the zone target was cleared
      updated_zone = Scenes.get_zone(scene.id, zone.id)
      assert is_nil(updated_zone.target_type)
      assert is_nil(updated_zone.target_id)
    end

    test "does nothing when no zone links to the deleted scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # Navigate to a non-existent scene — no zone links to it
      html =
        render_hook(view, "navigate_to_target", %{"type" => "scene", "id" => 999_999})

      assert html =~ "no longer exists"
    end

    test "ignores unsupported target types", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html = render_hook(view, "navigate_to_target", %{"type" => "flow", "id" => 1})
      assert html =~ "scene-canvas"
    end

    test "handles missing params gracefully", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html = render_hook(view, "navigate_to_target", %{})
      assert html =~ "scene-canvas"
    end
  end

  # ── handle_create_child_scene_from_zone ───────────────────────────

  describe "create_child_scene_from_zone event" do
    setup :register_and_log_in_user

    test "shows error for non-existent zone", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html =
        render_click(view, "create_child_scene_from_zone", %{"zone_id" => "999999"})

      assert html =~ "not found"
    end

    test "creates child scene without background when no image extraction possible",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      # Scene without a background — extract_zone_image will fail with :no_background_image
      scene = scene_fixture(project)

      zone =
        zone_fixture(scene, %{
          "name" => "Named Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})

      # Should redirect to the new child scene (with info flash about adding background)
      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"

      # Verify the child scene was created with the zone's name
      scenes = Scenes.list_scenes(project.id)
      child = Enum.find(scenes, &(&1.name == "Named Zone"))
      assert child != nil
      assert child.parent_id == scene.id
    end

    test "links zone to newly created child scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)

      zone =
        zone_fixture(scene, %{
          "name" => "Zone A",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})
      assert_redirect(view)

      # The zone should now be linked to the child scene
      updated_zone = Scenes.get_zone(scene.id, zone.id)
      assert updated_zone.target_type == "scene"
      assert updated_zone.target_id != nil

      # Verify child exists
      child = Scenes.get_scene(project.id, updated_zone.target_id)
      assert child != nil
      assert child.name == "Zone A"
    end

    test "creates child scene with inherited scale when parent has scale_value",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project)
      # Set scale_value on the parent scene
      {:ok, scene} = Scenes.update_scene(scene, %{scale_value: 1000.0, scale_unit: "meters"})

      zone =
        zone_fixture(scene, %{
          "name" => "Scaled Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"

      # Verify the child inherits scale
      scenes = Scenes.list_scenes(project.id)
      child = Enum.find(scenes, &(&1.name == "Scaled Zone"))
      assert child != nil
      assert child.scale_unit == "meters"
      # scale_value should be parent's * (bw_percent / 100)
      # vertices span 10..50 on X axis so bw_percent = 40
      assert child.scale_value != nil
    end

    test "creates child scene with full image extraction when background exists",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      # Copy test image to priv/static/uploads where ZoneImageExtractor can resolve it.
      src = Path.join(File.cwd!(), "test/fixtures/images/quadrant_map.png")
      dest = Path.join(File.cwd!(), "priv/static/uploads/test_quadrant.png")
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(src, dest)
      on_exit(fn -> File.rm(dest) end)

      asset = image_asset_fixture(project, user, %{url: "/uploads/test_quadrant.png"})

      scene = scene_fixture(project)
      {:ok, scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})
      scene = Storyarn.Repo.preload(scene, :background_asset, force: true)

      zone =
        zone_fixture(scene, %{
          "name" => "Extracted Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})

      # Should redirect to the new child scene
      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"

      # Verify the child scene was created
      scenes = Scenes.list_scenes(project.id)
      child = Enum.find(scenes, &(&1.name == "Extracted Zone"))
      assert child != nil
      assert child.parent_id == scene.id
    end

    test "falls back to no-image child scene when extraction fails (scene has background but image broken)",
         %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/broken.png"})
      scene = scene_fixture(project)
      {:ok, scene} = Scenes.update_scene(scene, %{background_asset_id: asset.id})

      zone =
        zone_fixture(scene, %{
          "name" => "Broken Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})

      # Should redirect — falls back to create_child_scene_without_image
      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"

      # Verify child was created
      scenes = Scenes.list_scenes(project.id)
      child = Enum.find(scenes, &(&1.name == "Broken Zone"))
      assert child != nil
    end

    test "rejected for viewer role", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      scene = scene_fixture(project)

      zone =
        zone_fixture(scene, %{
          "name" => "Zone B",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      html =
        render_click(view, "create_child_scene_from_zone", %{"zone_id" => to_string(zone.id)})

      # Viewer cannot create — page should remain
      assert html =~ "scene-canvas"

      # No child scene should be created
      scenes = Scenes.list_scenes(project.id)
      refute Enum.any?(scenes, &(&1.parent_id == scene.id))
    end
  end

  # ── Integration: set_pending + confirm_delete flow ────────────────

  describe "pending + confirm delete flow for current scene" do
    setup :register_and_log_in_user

    test "sets pending and confirms deletion of current scene", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, scene_url(project, scene))

      # Set pending delete to current scene
      render_click(view, "set_pending_delete_scene", %{"id" => to_string(scene.id)})

      # Confirm — should delete and redirect to index
      render_click(view, "confirm_delete_scene", %{})

      {path, _flash} = assert_redirect(view)
      assert path == scenes_index_url(project)
    end
  end
end
