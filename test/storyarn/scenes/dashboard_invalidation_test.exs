defmodule Storyarn.Scenes.DashboardInvalidationTest do
  @moduledoc """
  Pin and zone shortcuts ARE referenceable variables
  (`Flows.list_referenceable_variables/1`), so a write to either changes the
  vocabulary every health surface type-checks against — not just a dashboard
  count. Until now neither CRUD invalidated anything, which today reads as a
  ≤30s stale stat and becomes a wrong `stale_variable_reference` verdict the
  moment anything caches the vocabulary.

  Layers reach the same invalidation by a different route: they carry no
  shortcut, so they are not vocabulary, but their existence and `is_default`
  are finding inputs and deleting one nilifies the `layer_id` that
  `invalid_layer_reference` reads.

  What these tests pin is the invalidation itself: the cached sweep must not
  survive a write that moved either of those under it — and, just as
  deliberately, that the writes which move neither stay silent.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Scenes

  setup do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project, %{name: "Ruins"})
    Collaboration.subscribe_dashboard(project.id)
    %{project: project, scene: scene}
  end

  describe "a pin write invalidates the scenes dashboard" do
    test "on create", %{scene: scene} do
      {:ok, _pin} = Scenes.create_pin(scene.id, %{"position_x" => 10.0, "position_y" => 10.0, "label" => "Guard"})

      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on update, which is where a shortcut appears", %{scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})
      flush()

      {:ok, updated} = Scenes.update_pin(pin, %{"shortcut" => "guard"})

      assert updated.shortcut == "guard"
      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on delete", %{scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})
      flush()

      {:ok, _} = Scenes.delete_pin(pin)

      assert_receive {:dashboard_invalidate, :scenes}
    end
  end

  describe "a zone write invalidates the scenes dashboard" do
    test "on create", %{scene: scene} do
      {:ok, _zone} = Scenes.create_zone(scene.id, %{"name" => "Gate", "vertices" => triangle()})

      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on update, which is where a shortcut appears", %{scene: scene} do
      zone = zone_fixture(scene, %{"name" => "Gate"})
      flush()

      {:ok, updated} = Scenes.update_zone(zone, %{"shortcut" => "gate"})

      assert updated.shortcut == "gate"
      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on delete", %{scene: scene} do
      zone = zone_fixture(scene, %{"name" => "Gate"})
      flush()

      {:ok, _} = Scenes.delete_zone(zone)

      assert_receive {:dashboard_invalidate, :scenes}
    end
  end

  describe "the cached sweep does not survive a vocabulary change" do
    test "a pin gaining a shortcut drops the cached findings", %{project: project, scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})

      cached =
        DashboardCache.fetch(project.id, :scene_health, fn -> Scenes.list_dashboard_health_findings(project.id) end)

      assert DashboardCache.fetch(project.id, :scene_health, fn -> :recomputed end) == cached

      {:ok, _} = Scenes.update_pin(pin, %{"shortcut" => "guard"})

      # If this still returns the cached list, the vocabulary the next health run
      # type-checks against is one write behind the database.
      assert DashboardCache.fetch(project.id, :scene_health, fn -> :recomputed end) == :recomputed
    end
  end

  describe "a layer write invalidates the scenes dashboard" do
    # Layers carry no shortcut, so they are not vocabulary — but layer EXISTENCE
    # and `is_default` are read by `missing_scene_layer`, `missing_default_layer`
    # and `multiple_default_layers`, and deleting one nilifies the `layer_id`
    # behind `invalid_layer_reference`. A layer write can therefore create or
    # clear a finding while the dashboard serves the cached sweep.
    test "on create", %{scene: scene} do
      {:ok, _layer} = Scenes.create_layer(scene.id, %{"name" => "Background"})

      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on update, which is where is_default moves", %{scene: scene} do
      layer = layer_fixture(scene, %{"name" => "Background"})
      flush()

      {:ok, updated} = Scenes.update_layer(layer, %{"is_default" => true})

      assert updated.is_default
      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "on delete", %{scene: scene} do
      # `scene_fixture/2` already creates the default layer, and deleting the
      # last one is refused — so the deletable layer is a second one.
      layer = layer_fixture(scene, %{"name" => "Background"})
      flush()

      {:ok, _} = Scenes.delete_layer(layer)

      assert_receive {:dashboard_invalidate, :scenes}
    end
  end

  describe "the drag paths stay quiet on purpose" do
    test "reorder_layers/2 and toggle_layer_visibility/1 write no finding input", %{scene: scene} do
      first = layer_fixture(scene, %{"name" => "Background"})
      second = layer_fixture(scene, %{"name" => "Foreground"})
      flush()

      {:ok, _} = Scenes.reorder_layers(scene.id, [second.id, first.id])
      {:ok, _} = Scenes.toggle_layer_visibility(first)

      # No finding reads `position` or `visible`. If one ever does, this test is
      # the thing that has to fail.
      refute_receive {:dashboard_invalidate, :scenes}
    end

    test "move_pin/3 and update_zone_vertices/2 write coordinates, not vocabulary", %{scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})
      zone = zone_fixture(scene, %{"name" => "Gate"})
      flush()

      {:ok, _} = Scenes.move_pin(pin, 20.0, 20.0)
      {:ok, _} = Scenes.update_zone_vertices(zone, %{"vertices" => triangle()})

      # These fire on every drag. Their staleness is bounded by the dashboard's
      # own 30s cache; broadcasting per frame is not worth it.
      refute_receive {:dashboard_invalidate, :scenes}
    end
  end

  defp triangle do
    [%{"x" => 5.0, "y" => 5.0}, %{"x" => 40.0, "y" => 5.0}, %{"x" => 20.0, "y" => 40.0}]
  end

  defp flush do
    receive do
      {:dashboard_invalidate, _} -> flush()
    after
      0 -> :ok
    end
  end
end
