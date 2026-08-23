defmodule Storyarn.Scenes.VersioningTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.Versioning
  alias Storyarn.Scenes.Versioning.EntityVersionRecord
  alias Storyarn.Scenes.Versioning.RestorePolicy
  alias Storyarn.Scenes.Versioning.SceneSnapshot
  alias Storyarn.Scenes.Versioning.SnapshotStorage
  alias Storyarn.Versioning, as: LegacyVersioning

  setup do
    previous_policy = Application.get_env(:storyarn, RestorePolicy)
    Application.put_env(:storyarn, RestorePolicy, scene_version_restore: true)

    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project, %{name: "Opening", shortcut: "opening"})

    on_exit(fn ->
      if is_nil(previous_policy),
        do: Application.delete_env(:storyarn, RestorePolicy),
        else: Application.put_env(:storyarn, RestorePolicy, previous_policy)

      scene.id
      |> Versioning.list_versions()
      |> Enum.each(fn version ->
        _cleanup_result = SnapshotStorage.delete(version.storage_key)
      end)
    end)

    %{user: user, project: project, scene: scene}
  end

  describe "Scene-owned version lifecycle" do
    test "creates, verifies, lists, rate-limits, names, and deletes versions", %{
      user: user,
      scene: scene
    } do
      assert {:ok, %EntityVersionRecord{} = first} =
               Versioning.create_version(scene, user.id, title: "First")

      assert first.entity_type == "scene"
      assert first.entity_id == scene.id
      assert first.project_id == scene.project_id
      assert first.version_number == 1
      assert first.checksum =~ ~r/\A[0-9a-f]{64}\z/

      assert {:ok, snapshot} = Versioning.load_version_snapshot(first)
      assert snapshot["original_id"] == scene.id
      assert snapshot["name"] == "Opening"

      assert {:skipped, :too_recent} =
               Versioning.maybe_create_version(scene, user.id, min_interval: 600)

      assert {:ok, second} =
               Versioning.maybe_create_version(scene, user.id, min_interval: 0)

      assert second.version_number == 2
      assert Enum.map(Versioning.list_versions(scene.id), & &1.id) == [second.id, first.id]
      assert Versioning.get_version(scene.id, 1).id == first.id
      assert Versioning.get_latest_version(scene.id).id == second.id
      assert Versioning.count_versions(scene.id) == 2

      assert {:ok, promoted} =
               Versioning.update_version(second, %{title: "Checkpoint", description: "Ready"})

      refute promoted.is_auto
      assert promoted.title == "Checkpoint"

      assert {:ok, deleted} = Versioning.delete_version(first)
      assert deleted.id == first.id
      assert Versioning.get_version(scene.id, 1) == nil
      assert {:error, _reason} = Versioning.load_version_snapshot(first)
    end

    test "the legacy Versioning facade no longer exposes entity versioning", %{
      user: user,
      scene: scene
    } do
      assert {:ok, created} = Versioning.create_version(scene, user.id, title: "Scene owner")

      Code.ensure_loaded!(LegacyVersioning)

      for {fun, arity} <- [
            create_version: 5,
            maybe_create_version: 5,
            list_versions: 3,
            get_version: 3,
            get_latest_version: 2,
            count_versions: 2,
            get_adjacent_version_numbers: 3,
            count_versions_since: 3,
            update_version: 2,
            count_named_versions: 1,
            delete_version: 1,
            load_version_snapshot: 1,
            restore_version: 4,
            detect_restore_conflicts: 3,
            get_builder!: 1,
            next_version_number: 2
          ] do
        refute function_exported?(LegacyVersioning, fun, arity),
               "expected the legacy facade to no longer export #{fun}/#{arity}"
      end

      assert Versioning.get_version(scene.id, created.version_number).title == "Scene owner"
    end

    test "restores root and child state and creates a durable safety version", %{
      user: user,
      scene: scene
    } do
      first_pin = pin_fixture(scene, %{"label" => "First"})
      second_pin = pin_fixture(scene, %{"label" => "Second"})
      zone = zone_fixture(scene, %{"name" => "Gate"})
      annotation = annotation_fixture(scene, %{"text" => "Historical note"})
      connection = connection_fixture(scene, first_pin, second_pin)

      assert {:ok, target} = Versioning.create_version(scene, user.id, title: "Original")
      assert {:ok, changed_scene} = Scenes.update_scene(scene, %{name: "Changed"})
      assert {:ok, _deleted_pin} = Scenes.delete_pin(second_pin)
      assert {:ok, _deleted_zone} = Scenes.delete_zone(zone)
      assert {:ok, _deleted_annotation} = Scenes.delete_annotation(annotation)

      assert {:ok, restored} =
               Versioning.restore_version(changed_scene, target, user_id: user.id)

      assert restored.name == "Opening"
      assert Enum.any?(Scenes.list_pins(scene.id), &(&1.id == second_pin.id))
      assert Enum.any?(Scenes.list_zones(scene.id), &(&1.id == zone.id))
      assert Enum.any?(Scenes.list_annotations(scene.id), &(&1.id == annotation.id))
      assert Enum.any?(Scenes.list_connections(scene.id), &(&1.id == connection.id))

      versions = Versioning.list_versions(scene.id)
      assert length(versions) == 3
      assert Enum.any?(versions, &(&1.title == "Before restore to v1"))
      assert Enum.any?(versions, &(&1.title == "Restored from v1"))
    end

    test "rejects a version from another Scene without creating safety state", %{
      user: user,
      project: project,
      scene: scene
    } do
      other = scene_fixture(project)
      assert {:ok, other_version} = Versioning.create_version(other, user.id)

      assert {:error, :entity_version_scope_mismatch} =
               Versioning.restore_version(scene, other_version, user_id: user.id)

      assert Versioning.count_versions(scene.id) == 0
      _cleanup_result = SnapshotStorage.delete(other_version.storage_key)
    end

    test "restore policy fails closed", %{user: user, scene: scene} do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      Application.delete_env(:storyarn, RestorePolicy)

      refute Versioning.restore_enabled?()

      assert {:error, :restore_temporarily_disabled} =
               Versioning.restore_version(scene, target, user_id: user.id)

      assert Versioning.count_versions(scene.id) == 1
    end

    test "rejects restore inside an existing database transaction", %{user: user, scene: scene} do
      assert {:ok, target} = Versioning.create_version(scene, user.id)

      assert {:ok, :checked} =
               Repo.transaction(fn ->
                 assert {:error, :version_restore_requires_transaction_boundary} =
                          Versioning.restore_version(scene, target, user_id: user.id)

                 :checked
               end)

      assert Versioning.count_versions(scene.id) == 1
    end

    test "rejects a restore when Scene changes after its verified safety version", %{
      user: user,
      scene: scene
    } do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current"})

      hook = fn _safety_version ->
        current = Repo.get!(Scene, scene.id)
        assert {:ok, _changed} = Scenes.update_scene(current, %{name: "Concurrent"})
      end

      assert {:error, :scene_changed_since_pre_restore_snapshot} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: hook
               )

      assert Repo.get!(Scene, scene.id).name == "Concurrent"
      assert Versioning.count_versions(scene.id) == 2
      refute Enum.any?(Versioning.list_versions(scene.id), &String.starts_with?(&1.title || "", "Restored from"))
    end

    test "fails closed for malformed or non-durable safety-version identity", %{
      user: user,
      scene: scene
    } do
      target_snapshot = SceneSnapshot.build_snapshot(scene)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})
      pre_restore_snapshot = SceneSnapshot.build_snapshot(current)
      assert {:ok, safety_version} = Versioning.create_version(current, user.id)

      assert {:error, :invalid_pre_restore_version_identity} =
               SceneSnapshot.restore_snapshot(current, target_snapshot,
                 restore_action: {:entity_version_restore, "scene"},
                 user_id: user.id,
                 pre_restore_snapshot: pre_restore_snapshot,
                 pre_restore_version_identity: %{}
               )

      assert Repo.get!(Scene, scene.id).name == "Current state"

      identity = version_identity(safety_version)
      assert {:ok, _deleted} = Versioning.delete_version(safety_version)

      assert {:error, :pre_restore_version_not_durable} =
               SceneSnapshot.restore_snapshot(current, target_snapshot,
                 restore_action: {:entity_version_restore, "scene"},
                 user_id: user.id,
                 pre_restore_snapshot: pre_restore_snapshot,
                 pre_restore_version_identity: identity
               )

      assert Repo.get!(Scene, scene.id).name == "Current state"
    end

    test "full restore rejects a safety row deleted after verification", %{
      user: user,
      scene: scene
    } do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})
      test_pid = self()

      hook = fn safety_version ->
        send(test_pid, {:deleted_safety_key, safety_version.storage_key})
        Repo.delete!(safety_version)
      end

      assert {:error, :pre_restore_version_not_durable} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: hook
               )

      assert Repo.get!(Scene, scene.id).name == "Current state"
      assert Versioning.count_versions(scene.id) == 1
      assert_received {:deleted_safety_key, storage_key}
      _cleanup_result = SnapshotStorage.delete(storage_key)
    end

    test "full restore rejects a safety checksum changed after verification", %{
      user: user,
      scene: scene
    } do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})

      hook = fn safety_version ->
        Repo.update_all(
          from(version in EntityVersionRecord, where: version.id == ^safety_version.id),
          set: [checksum: String.duplicate("0", 64)]
        )
      end

      assert {:error, :pre_restore_version_identity_mismatch} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: hook
               )

      assert Repo.get!(Scene, scene.id).name == "Current state"
      assert Versioning.count_versions(scene.id) == 2
      refute Enum.any?(Versioning.list_versions(scene.id), &(&1.title == "Restored from v1"))
    end

    test "safety and post-restore snapshots preserve the exact before and after states", %{
      user: user,
      scene: scene
    } do
      pin = pin_fixture(scene, %{"label" => "Historical pin"})
      assert {:ok, target} = Versioning.create_version(scene, user.id)

      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})
      assert {:ok, _deleted_pin} = Scenes.delete_pin(pin)

      assert {:ok, restored} = Versioning.restore_version(current, target, user_id: user.id)
      assert restored.name == "Opening"

      versions = Versioning.list_versions(scene.id)
      safety = Enum.find(versions, &(&1.title == "Before restore to v1"))
      post_restore = Enum.find(versions, &(&1.title == "Restored from v1"))

      assert {:ok, safety_snapshot} = Versioning.load_version_snapshot(safety)
      assert safety_snapshot["name"] == "Current state"
      refute snapshot_contains_pin?(safety_snapshot, pin.id)

      assert {:ok, post_restore_snapshot} = Versioning.load_version_snapshot(post_restore)
      assert post_restore_snapshot["name"] == "Opening"
      assert snapshot_contains_pin?(post_restore_snapshot, pin.id)
    end

    test "skip_pre_snapshot cannot bypass the mandatory Scene safety version", %{
      user: user,
      scene: scene
    } do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})

      assert {:ok, restored} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 skip_pre_snapshot: true
               )

      assert restored.name == "Opening"

      versions = Versioning.list_versions(scene.id)
      assert length(versions) == 3
      assert Enum.any?(versions, &(&1.title == "Before restore to v1"))
      assert Enum.any?(versions, &(&1.title == "Restored from v1"))
    end

    test "safety creation failure aborts before mutating the Scene", %{
      user: user,
      scene: scene
    } do
      assert {:ok, target} = Versioning.create_version(scene, user.id)
      assert {:ok, current} = Scenes.update_scene(scene, %{name: "Current state"})

      create_safety = fn _scene, _user_id, _opts -> {:error, :simulated_failure} end

      assert {:error, {:pre_restore_snapshot_failed, :simulated_failure}} =
               Versioning.restore_version(current, target,
                 user_id: user.id,
                 __pre_restore_version_fun: create_safety
               )

      assert Repo.get!(Scene, scene.id).name == "Current state"
      assert Versioning.count_versions(scene.id) == 1
    end

    test "restores safely when the version actor is nil", %{scene: scene} do
      assert {:ok, target} = Versioning.create_version(scene, nil)
      assert {:ok, changed} = Scenes.update_scene(scene, %{name: "Changed without actor"})

      assert {:ok, restored} = Versioning.restore_version(changed, target, user_id: nil)
      assert restored.name == scene.name

      versions = Versioning.list_versions(scene.id)
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.title == "Before restore to v1" and is_nil(&1.created_by_id)))
    end

    test "previews missing references and shortcut collisions with Scene-owned records", %{
      project: project,
      scene: scene
    } do
      pin = pin_fixture(scene)
      snapshot = SceneSnapshot.build_snapshot(scene)
      other = scene_fixture(project)

      snapshot =
        snapshot
        |> Map.put("shortcut", other.shortcut)
        |> Map.update!("orphan_pins", fn pins ->
          Enum.map(pins, fn
            %{"original_id" => id} = current when id == pin.id ->
              Map.put(current, "sheet_id", 9_999_999)

            current ->
              current
          end)
        end)

      report = Versioning.detect_restore_conflicts(snapshot, scene)

      assert report.has_conflicts
      assert report.shortcut_collision
      assert report.resolved_shortcut == other.shortcut <> "-restored"
      assert Enum.any?(report.conflicts, &(&1.type == :sheet and &1.id == 9_999_999))
    end
  end

  describe "named version capacity" do
    test "blocks a new named version when the project is at the limit", %{
      user: user,
      project: project,
      scene: scene
    } do
      seed_named_versions(scene, 10)

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Scenes.create_version(scene, user.id, title: "Over the limit", skip_diff: true)

      assert Scenes.count_versions(scene.id) == 10

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Scenes.can_create_named_version?(project.id, project.workspace_id)
    end

    test "allows an automatic version when the named-version limit is full", %{
      user: user,
      project: project,
      scene: scene
    } do
      seed_named_versions(scene, 10)

      assert {:ok, %EntityVersionRecord{} = automatic} =
               Scenes.maybe_create_version(scene, user.id,
                 min_interval: 0,
                 skip_diff: true
               )

      assert automatic.is_auto
      assert is_nil(automatic.title)
      assert Scenes.count_versions(scene.id) == 11

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Scenes.can_create_named_version?(project.id, project.workspace_id)
    end

    test "blocks promotion of an automatic version when the project is at the limit", %{
      project: project,
      scene: scene
    } do
      seed_named_versions(scene, 10)
      automatic = insert_version!(scene, 11, %{is_auto: true, title: nil})

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Scenes.update_version(automatic, %{title: "Blocked promotion"})

      persisted = Scenes.get_version(scene.id, automatic.version_number)
      assert persisted.is_auto
      assert is_nil(persisted.title)
      assert named_version_count(project.id) == 10
    end

    test "allows editing an existing named version when the project is at the limit", %{
      project: project,
      scene: scene
    } do
      [existing | _versions] = seed_named_versions(scene, 10)

      assert {:ok, %EntityVersionRecord{} = updated} =
               Scenes.update_version(existing, %{
                 title: "Renamed checkpoint",
                 description: "Still occupies the same quota slot"
               })

      assert updated.title == "Renamed checkpoint"
      assert updated.description == "Still occupies the same quota slot"
      refute updated.is_auto
      assert named_version_count(project.id) == 10
    end
  end

  defp seed_named_versions(scene, count) do
    Enum.map(1..count, fn version_number ->
      insert_version!(scene, version_number, %{title: "Checkpoint #{version_number}"})
    end)
  end

  defp insert_version!(scene, version_number, attrs) do
    base_attrs = %{
      entity_type: "scene",
      entity_id: scene.id,
      project_id: scene.project_id,
      version_number: version_number,
      title: nil,
      description: nil,
      storage_key: "projects/#{scene.project_id}/snapshots/scene/#{scene.id}/test-#{version_number}.json.gz",
      snapshot_size_bytes: 0,
      checksum: String.duplicate("a", 64),
      is_auto: false
    }

    %EntityVersionRecord{}
    |> EntityVersionRecord.create_changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp named_version_count(project_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.project_id == ^project_id and not is_nil(version.title) and
            version.is_auto == false
      ),
      :count
    )
  end

  defp version_identity(%EntityVersionRecord{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp snapshot_contains_pin?(snapshot, pin_id) do
    layered_pins =
      snapshot
      |> Map.get("layers", [])
      |> Enum.flat_map(&Map.get(&1, "pins", []))

    Enum.any?(layered_pins ++ Map.get(snapshot, "orphan_pins", []), fn pin ->
      pin["original_id"] == pin_id
    end)
  end
end
