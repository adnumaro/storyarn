defmodule Storyarn.Versioning.ProjectSnapshotResetTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.SnapshotResetStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotStorage

  @environment "reset-test"
  @authorization String.duplicate("a", 32)

  test "dry run and execution remain exact to one environment and workspace" do
    user = user_fixture()
    project = project_fixture(user)
    other_user = user_fixture()
    other_project = project_fixture(other_user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    other_snapshot = full_project_snapshot_fixture(other_project, %{asset_blob_size_bytes: 0})
    entity_version = entity_version_fixture(project)
    other_entity_version = entity_version_fixture(other_project)

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes,
        entity_version.storage_key => entity_version.snapshot_size_bytes,
        other_snapshot.project_storage_key => other_snapshot.project_size_bytes,
        other_snapshot.manifest_storage_key => other_snapshot.manifest_size_bytes,
        other_entity_version.storage_key => other_entity_version.snapshot_size_bytes
      })

    assert {:ok, plan} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, @environment,
               current_environment: @environment,
               storage_adapter: SnapshotResetStorage
             )

    assert plan["status"] == "prepared"
    assert plan["workspace_id"] == project.workspace_id
    assert plan["project_ids"] == [project.id]
    assert plan["snapshot_row_ids"] == [snapshot.id]
    assert plan["entity_version_row_ids"] == [entity_version.id]

    assert plan["objects"] |> Enum.map(& &1["key"]) |> Enum.sort() ==
             Enum.sort([
               snapshot.project_storage_key,
               snapshot.manifest_storage_key,
               entity_version.storage_key
             ])

    handler_id = "snapshot-reset-stop-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :reset, :stop],
        fn event, measurements, metadata, test_pid ->
          send(test_pid, {:snapshot_reset_stop, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, :snapshot_reset_inventory_confirmation_mismatch, ^plan} =
             Versioning.execute_project_snapshot_reset(plan, String.duplicate("b", 64),
               current_environment: @environment,
               expected_authorization: @authorization,
               authorization: @authorization,
               storage_adapter: SnapshotResetStorage
             )

    assert {:ok, completed} = execute(plan)
    assert completed["status"] == "completed"
    assert completed["remaining_storage_keys"] == []
    assert {:ok, ^completed} = execute(completed)
    refute Repo.get(ProjectSnapshot, snapshot.id)
    refute Repo.get(EntityVersion, entity_version.id)
    assert Repo.get!(ProjectSnapshot, other_snapshot.id).lifecycle_state == "ready"
    assert Repo.get!(EntityVersion, other_entity_version.id)
    assert Map.has_key?(SnapshotResetStorage.objects(), other_snapshot.manifest_storage_key)
    assert Map.has_key?(SnapshotResetStorage.objects(), other_entity_version.storage_key)

    assert_receive {:snapshot_reset_stop, [:storyarn, :snapshot, :reset, :stop],
                    %{object_count: 3, snapshot_row_count: 1, entity_version_row_count: 1, attempt_count: 1},
                    %{status: :completed, workspace_id: workspace_id, inventory_digest: inventory_digest}}

    assert workspace_id == project.workspace_id
    assert inventory_digest == completed["inventory_digest"]
  end

  test "rejects the wrong deployment environment before listing or deleting" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})

    assert {:error, :snapshot_reset_environment_mismatch} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, "production",
               current_environment: "staging",
               storage_adapter: SnapshotResetStorage
             )
  end

  test "checkpoints provider failure and resumes from the same immutable plan" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)
    :ok = SnapshotResetStorage.fail_once([snapshot.manifest_storage_key])

    checkpoint = fn checkpointed ->
      send(self(), {:checkpointed_reset, checkpointed})
      :ok
    end

    assert {:error, :snapshot_reset_storage_delete_failed, failed} =
             execute(plan, checkpoint: checkpoint)

    assert failed["status"] == "failed"
    assert failed["remaining_storage_keys"] == [snapshot.manifest_storage_key]
    assert_received {:checkpointed_reset, %{"status" => "failed", "remaining_storage_keys" => [_key]}}
    assert Repo.get!(ProjectSnapshot, snapshot.id)

    assert {:ok, completed} = execute(failed)
    assert completed["attempt_count"] == 2
    refute Repo.get(ProjectSnapshot, snapshot.id)
  end

  test "recovers a completed reset when only the final audit checkpoint failed" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)

    checkpoint = fn checkpointed ->
      send(self(), {:reset_checkpoint, checkpointed})
      if checkpointed["status"] == "completed", do: {:error, :audit_storage_unavailable}, else: :ok
    end

    assert {:error, {:snapshot_reset_checkpoint_failed, :audit_storage_unavailable}, completed} =
             execute(plan, checkpoint: checkpoint)

    assert completed["status"] == "completed"
    checkpoints = collect_checkpoints([])
    stale_plan = checkpoints |> Enum.reject(&(&1["status"] == "completed")) |> List.last()
    assert stale_plan["status"] == "running"
    assert stale_plan["remaining_storage_keys"] == []
    refute Repo.get(ProjectSnapshot, snapshot.id)

    assert {:ok, recovered} = execute(stale_plan)
    assert recovered["status"] == "completed"
    assert recovered["attempt_count"] == stale_plan["attempt_count"] + 1

    _new_version = entity_version_fixture(project)

    assert {:error, :snapshot_reset_completed_state_changed, ^recovered} = execute(recovered)
  end

  test "fails closed on a key outside the canonical snapshot-owned layout" do
    user = user_fixture()
    project = project_fixture(user)
    unsafe = "projects/#{project.id}/snapshots/object-sets/v1/ready/not-a-token/project.json"
    :ok = SnapshotResetStorage.put_objects(%{unsafe => 10})

    assert {:error, :unsafe_snapshot_reset_object} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, @environment,
               current_environment: @environment,
               storage_adapter: SnapshotResetStorage
             )
  end

  test "fails closed before loading an oversized database inventory" do
    user = user_fixture()
    project = project_fixture(user)
    _first = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    _second = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    :ok = SnapshotResetStorage.put_objects(%{})

    assert {:error, :snapshot_reset_database_inventory_limit_exceeded} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, @environment,
               current_environment: @environment,
               storage_adapter: SnapshotResetStorage,
               max_objects: 1
             )
  end

  test "rejects tampered prefixes and unexpected plan metadata" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    assert {:error, :invalid_snapshot_reset_plan} =
             plan
             |> Map.put("prefixes", ["projects/#{project.id}/assets/"])
             |> Versioning.validate_project_snapshot_reset_plan()

    assert {:error, :invalid_snapshot_reset_plan} =
             plan
             |> Map.put("untrusted_metadata", "ignored-before-eng-80")
             |> Versioning.validate_project_snapshot_reset_plan()

    assert {:error, :invalid_snapshot_reset_plan} =
             plan
             |> Map.put("snapshot_row_ids", [System.unique_integer([:positive])])
             |> Versioning.validate_project_snapshot_reset_plan()
  end

  defp prepare(workspace_id) do
    Versioning.prepare_project_snapshot_reset(workspace_id, @environment,
      current_environment: @environment,
      storage_adapter: SnapshotResetStorage
    )
  end

  defp execute(plan, opts \\ []) do
    defaults = [
      current_environment: @environment,
      expected_authorization: @authorization,
      authorization: @authorization,
      storage_adapter: SnapshotResetStorage
    ]

    Versioning.execute_project_snapshot_reset(
      plan,
      plan["inventory_digest"],
      Keyword.merge(defaults, opts)
    )
  end

  defp collect_checkpoints(checkpoints) do
    receive do
      {:reset_checkpoint, checkpoint} -> collect_checkpoints([checkpoint | checkpoints])
    after
      0 -> Enum.reverse(checkpoints)
    end
  end

  defp entity_version_fixture(project) do
    entity_id = System.unique_integer([:positive])
    version_number = 1

    attrs = %{
      entity_type: "sheet",
      entity_id: entity_id,
      project_id: project.id,
      version_number: version_number,
      storage_key:
        SnapshotStorage.build_key(
          project.id,
          "sheet",
          entity_id,
          version_number,
          8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
        ),
      snapshot_size_bytes: 128,
      checksum: String.duplicate("a", 64),
      is_auto: false
    }

    %EntityVersion{}
    |> EntityVersion.changeset(attrs)
    |> Repo.insert!()
  end
end
