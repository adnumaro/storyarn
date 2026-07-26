defmodule Storyarn.Scenes.DashboardInvalidationTest do
  @moduledoc """
  Pin and zone shortcuts ARE referenceable variables
  (`Flows.list_referenceable_variables/1`), so a write to either changes the
  vocabulary every health surface type-checks against — not just a dashboard
  count. Until now neither CRUD invalidated anything, which today reads as a
  ≤30s stale stat and becomes a wrong `stale_variable_reference` verdict the
  moment anything caches the vocabulary.

  What these tests pin is the invalidation itself: the cached sweep must not
  survive a write that moved the vocabulary under it.
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

      cached = DashboardCache.fetch(project.id, :scene_health, fn -> Scenes.list_dashboard_health_findings(project.id) end)
      assert DashboardCache.fetch(project.id, :scene_health, fn -> :recomputed end) == cached

      {:ok, _} = Scenes.update_pin(pin, %{"shortcut" => "guard"})

      # If this still returns the cached list, the vocabulary the next health run
      # type-checks against is one write behind the database.
      assert DashboardCache.fetch(project.id, :scene_health, fn -> :recomputed end) == :recomputed
    end
  end

  describe "the drag paths stay quiet on purpose" do
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
