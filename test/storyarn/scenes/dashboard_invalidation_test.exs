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

  Coordinates and vertices are findings inputs too: they drive
  `element_outside_canvas` and `invalid_zone_geometry`. What these tests pin is
  the invalidation itself: the cached sweep must not survive any write that
  changes one of those inputs — and, just as deliberately, writes which move no
  finding input stay silent.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Repo
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

  describe "restoring a scene invalidates the scenes dashboard" do
    test "only after the restore transaction commits", %{scene: scene} do
      assert {:ok, _deleted} = Scenes.delete_scene(scene)
      flush()

      deleted = Scenes.get_scene_including_deleted(scene.project_id, scene.id)
      assert {:ok, restored} = Scenes.restore_scene(deleted)

      assert is_nil(restored.deleted_at)
      assert_receive {:dashboard_invalidate, :scenes}
      refute_receive {:dashboard_invalidate, :scenes}, 10
    end

    test "a rejected restore emits nothing", %{scene: scene} do
      assert {:error, :scene_not_deleted} = Scenes.restore_scene(scene)
      refute_receive {:dashboard_invalidate, :scenes}, 10
    end
  end

  describe "updating a scene invalidates its persisted owner" do
    test "does not trust a stale struct's project_id", %{project: project, scene: scene} do
      unrelated_project = project_fixture()
      subscribe_dashboard_probe(unrelated_project.id, :unrelated)
      flush()

      stale_scene = %{scene | project_id: unrelated_project.id}

      assert {:ok, updated} = Scenes.update_scene(stale_scene, %{name: "Updated ruins"})
      assert updated.project_id == project.id
      assert_receive {:dashboard_invalidate, :scenes}
      refute_receive {:dashboard_probe, :unrelated, {:dashboard_invalidate, :scenes}}, 50
    end
  end

  describe "health-neutral writes stay quiet" do
    test "reorder_layers/2 and toggle_layer_visibility/1 write no finding input", %{scene: scene} do
      first = layer_fixture(scene, %{"name" => "Background"})
      second = layer_fixture(scene, %{"name" => "Foreground"})
      findings_before = Scenes.list_dashboard_health_findings(scene.project_id)
      flush()

      {:ok, _} = Scenes.reorder_layers(scene.id, [second.id, first.id])
      {:ok, _} = Scenes.toggle_layer_visibility(first)

      # Keep the missing invalidation coupled to its premise: these fields do
      # not currently affect dashboard health. If a checker starts reading
      # either field, this assertion forces the writer contract to be updated.
      assert Scenes.list_dashboard_health_findings(scene.project_id) == findings_before
      refute_receive {:dashboard_invalidate, :scenes}
    end
  end

  describe "coordinate writes invalidate the scenes dashboard" do
    test "move_pin/3 invalidates because position drives element_outside_canvas", %{scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})
      flush()

      {:ok, _} = Scenes.move_pin(pin, 120.0, 20.0)

      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "update_zone_vertices/2 invalidates because vertices drive geometry findings", %{scene: scene} do
      zone = zone_fixture(scene, %{"name" => "Gate"})
      flush()

      {:ok, _} =
        Scenes.update_zone_vertices(zone, %{
          "vertices" => [
            %{"x" => 5.0, "y" => 5.0},
            %{"x" => 140.0, "y" => 5.0},
            %{"x" => 20.0, "y" => 40.0}
          ]
        })

      assert_receive {:dashboard_invalidate, :scenes}
    end

    test "moving a pin outside the canvas drops the cached health sweep", %{project: project, scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard", "position_x" => 20.0, "position_y" => 20.0})
      flush()

      initial =
        DashboardCache.fetch(project.id, :scene_health, fn -> Scenes.list_dashboard_health_findings(project.id) end)

      refute Enum.any?(initial, &(&1.code == :element_outside_canvas and &1.entity_id == pin.id))

      {:ok, _} = Scenes.move_pin(pin, 120.0, 20.0)

      refreshed =
        DashboardCache.fetch(project.id, :scene_health, fn -> Scenes.list_dashboard_health_findings(project.id) end)

      assert Enum.any?(refreshed, &(&1.code == :element_outside_canvas and &1.entity_id == pin.id))
    end

    test "drag invalidation reuses the project id already locked by the transaction", %{scene: scene} do
      pin = pin_fixture(scene, %{"label" => "Guard"})
      zone = zone_fixture(scene, %{"name" => "Gate"})
      handler_id = "scene-drag-owner-lookup-#{System.unique_integer([:positive])}"
      marker = make_ref()
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :repo, :query],
          fn _event, _measurements, %{query: query}, {pid, ref} ->
            if self() == pid and
                 not Repo.in_transaction?() and
                 String.contains?(query, ~s(FROM "scenes")) do
              send(pid, {ref, query})
            end
          end,
          {test_pid, marker}
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, _pin} = Scenes.move_pin(pin, 30.0, 40.0)
      assert {:ok, _zone} = Scenes.update_zone_vertices(zone, %{"vertices" => triangle()})

      refute_receive {^marker, _redundant_owner_lookup}
    end
  end

  describe "connection and annotation writes invalidate at the context boundary" do
    test "a connection create emits exactly one post-commit event", %{scene: scene} do
      first = pin_fixture(scene, %{"label" => "First"})
      second = pin_fixture(scene, %{"label" => "Second"})
      flush()

      assert {:ok, _connection} =
               Scenes.create_connection(scene.id, %{
                 "from_pin_id" => first.id,
                 "to_pin_id" => second.id
               })

      assert_receive {:dashboard_invalidate, :scenes}
      refute_receive {:dashboard_invalidate, :scenes}, 10
    end

    test "an annotation move emits exactly one post-commit event", %{scene: scene} do
      annotation = annotation_fixture(scene, %{"text" => "Move me"})
      flush()

      assert {:ok, _annotation} = Scenes.move_annotation(annotation, 90.0, 90.0)

      assert_receive {:dashboard_invalidate, :scenes}
      refute_receive {:dashboard_invalidate, :scenes}, 10
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

  defp subscribe_dashboard_probe(project_id, tag) do
    test_pid = self()

    pid =
      spawn(fn ->
        Collaboration.subscribe_dashboard(project_id)
        send(test_pid, {:dashboard_probe_ready, tag})
        forward_dashboard_messages(test_pid, tag)
      end)

    assert_receive {:dashboard_probe_ready, ^tag}
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp forward_dashboard_messages(test_pid, tag) do
    receive do
      message ->
        send(test_pid, {:dashboard_probe, tag, message})
        forward_dashboard_messages(test_pid, tag)
    end
  end
end
