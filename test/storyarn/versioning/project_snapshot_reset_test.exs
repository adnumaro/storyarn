defmodule Storyarn.Versioning.ProjectSnapshotResetTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Release
  alias Storyarn.SnapshotResetStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotReset
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
               rollout_guard: &allow_pre_rollout/1,
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
               expected_authorization_digest: authorization_digest(),
               authorization: @authorization,
               rollout_guard: &allow_pre_rollout/1,
               storage_adapter: SnapshotResetStorage
             )

    assert_receive {:snapshot_reset_stop, [:storyarn, :snapshot, :reset, :stop],
                    %{object_count: 3, snapshot_row_count: 1, entity_version_row_count: 1, attempt_count: 0},
                    %{status: :error, error_code: error_code, workspace_id: workspace_id}}

    assert error_code =~ "snapshot_reset_inventory_confirmation_mismatch"
    assert workspace_id == project.workspace_id

    assert {:ok, completed} = execute(plan)
    assert completed["status"] == "completed"
    assert completed["remaining_storage_keys"] == []

    project_id = project.id

    assert [[[^project_id], @environment, inventory_digest, 3, 1]] =
             Repo.query!(
               """
               SELECT project_ids, environment, inventory_digest, object_count, attempt_count
               FROM project_snapshot_reset_receipts
               WHERE workspace_id = $1
               """,
               [project.workspace_id]
             ).rows

    assert inventory_digest == completed["inventory_digest"]
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

  test "refuses preparation and execution after the ENG-80 lifecycle rollout migration" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})

    assert {:error, :snapshot_reset_rollout_already_applied} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, @environment,
               current_environment: @environment,
               storage_adapter: SnapshotResetStorage
             )

    assert {:ok, plan} = prepare(project.workspace_id)

    assert {:error, :snapshot_reset_rollout_already_applied, ^plan} =
             Versioning.execute_project_snapshot_reset(plan, plan["inventory_digest"],
               current_environment: @environment,
               expected_authorization_digest: authorization_digest(),
               authorization: @authorization,
               storage_adapter: SnapshotResetStorage
             )
  end

  test "release execution rejects a symlinked authorization secret" do
    directory = Path.join(System.tmp_dir!(), "storyarn-reset-auth-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    target = Path.join(directory, "authorization")
    symlink = Path.join(directory, "authorization-link")
    on_exit(fn -> File.rm_rf(directory) end)
    File.write!(target, String.duplicate("a", 32))
    File.chmod!(target, 0o600)
    assert :ok = File.ln_s(target, symlink)

    assert_raise RuntimeError, ~r/owner-only regular file/, fn ->
      Release.execute_project_snapshot_reset(
        @environment,
        1,
        Path.join(directory, "unused-plan.json"),
        String.duplicate("b", 64),
        symlink
      )
    end
  end

  test "requires an independently configured authorization digest" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    common = [
      current_environment: @environment,
      expected_authorization_digest: authorization_digest(),
      rollout_guard: &allow_pre_rollout/1,
      storage_adapter: SnapshotResetStorage
    ]

    assert {:error, :snapshot_reset_not_authorized, ^plan} =
             Versioning.execute_project_snapshot_reset(plan, plan["inventory_digest"], common)

    assert {:error, :snapshot_reset_not_authorized, ^plan} =
             Versioning.execute_project_snapshot_reset(
               plan,
               plan["inventory_digest"],
               Keyword.put(common, :authorization, String.duplicate("b", 32))
             )
  end

  test "rechecks the deployment environment at execution" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    assert {:error, :snapshot_reset_environment_mismatch, ^plan} =
             execute(plan, current_environment: "another-environment")
  end

  test "rejects a same-size provider replacement before deleting" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)
    :ok = SnapshotResetStorage.replace_object(snapshot.manifest_storage_key, snapshot.manifest_size_bytes)

    assert {:error, :snapshot_reset_storage_scope_changed, ^plan} = execute(plan)
    assert Repo.get!(ProjectSnapshot, snapshot.id)
    assert Map.has_key?(SnapshotResetStorage.objects(), snapshot.manifest_storage_key)
  end

  test "conditional deletion fails closed when an object changes after inventory validation" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)
    [first_key | _rest] = plan["remaining_storage_keys"]
    :ok = SnapshotResetStorage.replace_before_delete([first_key])

    assert {:error, :snapshot_reset_storage_scope_changed, failed} = execute(plan)
    assert failed["status"] == "failed"
    assert failed["remaining_storage_keys"] == plan["remaining_storage_keys"]
    assert Map.has_key?(SnapshotResetStorage.objects(), first_key)
    assert Repo.get!(ProjectSnapshot, snapshot.id)
  end

  test "zero-state recovery rejects a changed project scope and its orphan snapshot root" do
    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    project = project_fixture(user, %{workspace: workspace})
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    new_project = project_fixture(user, %{workspace: workspace})
    orphan = "projects/#{new_project.id}/snapshots/project/orphan.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{orphan => 17})

    assert {:error, :snapshot_reset_database_scope_changed, ^plan} = execute(plan)
    assert Map.has_key?(SnapshotResetStorage.objects(), orphan)
  end

  test "rejects a changed database inventory even when row ids are unchanged" do
    user = user_fixture()
    project = project_fixture(user)
    entity_version = entity_version_fixture(project)
    :ok = SnapshotResetStorage.put_objects(%{entity_version.storage_key => entity_version.snapshot_size_bytes})
    assert {:ok, plan} = prepare(project.workspace_id)

    Repo.query!("UPDATE entity_versions SET title = 'changed after review' WHERE id = $1", [entity_version.id])

    assert {:error, :snapshot_reset_database_scope_changed, ^plan} = execute(plan)
    assert Repo.get!(EntityVersion, entity_version.id)
  end

  test "fails closed on unsafe persisted entity-version row metadata" do
    user = user_fixture()
    project = project_fixture(user)
    entity_version = entity_version_fixture(project)
    :ok = SnapshotResetStorage.put_objects(%{})

    Repo.query!("UPDATE entity_versions SET storage_key = $1 WHERE id = $2", [
      "projects/#{project.id}/assets/not-reset-owned.json",
      entity_version.id
    ])

    assert {:error, :unsafe_entity_version_reset_row_identity} = prepare(project.workspace_id)
  end

  test "uses a bounded number of full-plan checkpoints for a large inventory" do
    user = user_fixture()
    project = project_fixture(user)

    objects =
      Map.new(1..3_201, fn index ->
        {"projects/#{project.id}/snapshots/project/#{index}.json.gz", index}
      end)

    :ok = SnapshotResetStorage.put_objects(objects)
    assert {:ok, plan} = prepare(project.workspace_id)

    checkpoint = fn checkpointed ->
      send(self(), {:bounded_checkpoint, checkpointed["status"]})
      :ok
    end

    assert {:ok, completed} = execute(plan, checkpoint: checkpoint)
    assert completed["remaining_storage_keys"] == []
    assert length(collect_tagged_messages(:bounded_checkpoint, [])) <= 35
  end

  test "round-trips an owner-only immutable audit plan and atomic checkpoint" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    directory = Path.join(System.tmp_dir!(), "storyarn-reset-#{System.unique_integer([:positive])}")
    path = Path.join(directory, "plan.json")
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf(directory) end)

    assert :ok = ProjectSnapshotReset.write_new_plan_file(path, plan)

    assert {:error, :snapshot_reset_plan_exists} =
             ProjectSnapshotReset.write_new_plan_file(path, plan)

    assert {:ok, ^plan} = ProjectSnapshotReset.read_plan_file(path)
    assert :ok = ProjectSnapshotReset.write_plan_file(path, plan)
    assert {:ok, ^plan} = ProjectSnapshotReset.read_plan_file(path)
    assert Bitwise.band(File.stat!(path).mode, 0o077) == 0

    assert :ok = File.chmod(path, 0o644)
    assert {:error, :unsafe_snapshot_reset_plan_file} = ProjectSnapshotReset.read_plan_file(path)
    assert :ok = File.chmod(path, 0o600)

    symlink = path <> ".link"
    on_exit(fn -> File.rm(symlink) end)
    assert :ok = File.ln_s(path, symlink)
    assert {:error, :unsafe_snapshot_reset_plan_file} = ProjectSnapshotReset.read_plan_file(symlink)
  end

  test "refuses to persist plans outside an owner-only directory" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    directory = Path.join(System.tmp_dir!(), "storyarn-reset-unsafe-#{System.unique_integer([:positive])}")
    path = Path.join(directory, "plan.json")
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o755)
    on_exit(fn -> File.rm_rf(directory) end)

    assert {:error, {:snapshot_reset_plan_persist_failed, :unsafe_snapshot_reset_plan_directory}} =
             ProjectSnapshotReset.write_new_plan_file(path, plan)

    refute File.exists?(path)
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
    assert failed["remaining_storage_keys"] == plan["remaining_storage_keys"]
    assert_received {:checkpointed_reset, %{"status" => "failed", "remaining_storage_keys" => [_first_key, _second_key]}}
    assert Repo.get!(ProjectSnapshot, snapshot.id)

    assert {:ok, completed} = execute(failed)
    assert completed["attempt_count"] == 2
    refute Repo.get(ProjectSnapshot, snapshot.id)
  end

  test "checkpoints only the unprocessed suffix after a partial provider failure" do
    user = user_fixture()
    project = project_fixture(user)
    first = "projects/#{project.id}/snapshots/project/1.json.gz"
    second = "projects/#{project.id}/snapshots/project/2.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{first => 1, second => 2})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert plan["remaining_storage_keys"] == [first, second]
    :ok = SnapshotResetStorage.fail_once([second])

    checkpoint = fn checkpointed ->
      send(self(), {:partial_checkpoint, checkpointed})
      :ok
    end

    assert {:error, :snapshot_reset_storage_delete_failed, failed} =
             execute(plan, checkpoint: checkpoint)

    assert failed["remaining_storage_keys"] == [second]
    refute Map.has_key?(SnapshotResetStorage.objects(), first)
    assert Map.has_key?(SnapshotResetStorage.objects(), second)
    assert_receive {:partial_checkpoint, %{"status" => "failed", "remaining_storage_keys" => [^second]}}

    assert {:ok, completed} = execute(failed)
    assert completed["remaining_storage_keys"] == []
  end

  test "resumes idempotently when an object was deleted before its checkpoint" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)
    [already_deleted | _remaining] = plan["remaining_storage_keys"]
    assert :ok = SnapshotResetStorage.delete(already_deleted)

    assert {:ok, completed} = execute(plan)
    assert completed["remaining_storage_keys"] == []
    assert SnapshotResetStorage.objects() == %{}
    refute Repo.get(ProjectSnapshot, snapshot.id)
  end

  test "persists a database receipt that rejects mutation" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "UPDATE project_snapshot_reset_receipts SET object_count = object_count + 1 WHERE workspace_id = $1",
        [project.workspace_id]
      )
    end
  end

  test "receipt project inventory makes a post-reset project fail the rollout gate" do
    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    project = project_fixture(user, %{workspace: workspace})
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    _new_project = project_fixture(user, %{workspace: workspace})

    assert [[true]] =
             Repo.query!(
               """
               SELECT EXISTS (
                 SELECT 1
                 FROM workspaces w
                 LEFT JOIN project_snapshot_reset_receipts r ON r.workspace_id = w.id
                 WHERE w.id = $1 AND
                       (r.workspace_id IS NULL OR
                        r.project_ids <> ARRAY(
                          SELECT p.id
                          FROM projects p
                          WHERE p.workspace_id = w.id
                          ORDER BY p.id
                        ))
               )
               """,
               [workspace.id]
             ).rows
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

    assert [[receipt_attempt_count]] =
             Repo.query!(
               "SELECT attempt_count FROM project_snapshot_reset_receipts WHERE workspace_id = $1",
               [project.workspace_id]
             ).rows

    assert receipt_attempt_count == stale_plan["attempt_count"]

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
               rollout_guard: &allow_pre_rollout/1,
               storage_adapter: SnapshotResetStorage
             )
  end

  test "inventories the whole snapshot root and rejects an unexpected child namespace" do
    user = user_fixture()
    project = project_fixture(user)
    unexpected = "projects/#{project.id}/snapshots/object-sets/v2/ready/new-format/manifest.json"
    :ok = SnapshotResetStorage.put_objects(%{unexpected => 10})

    assert {:error, :unsafe_snapshot_reset_object} = prepare(project.workspace_id)
    assert Map.has_key?(SnapshotResetStorage.objects(), unexpected)
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
               rollout_guard: &allow_pre_rollout/1,
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
      rollout_guard: &allow_pre_rollout/1,
      storage_adapter: SnapshotResetStorage
    )
  end

  defp execute(plan, opts \\ []) do
    defaults = [
      current_environment: @environment,
      expected_authorization_digest: authorization_digest(),
      authorization: @authorization,
      rollout_guard: &allow_pre_rollout/1,
      storage_adapter: SnapshotResetStorage
    ]

    Versioning.execute_project_snapshot_reset(
      plan,
      plan["inventory_digest"],
      Keyword.merge(defaults, opts)
    )
  end

  defp allow_pre_rollout(_repo), do: :ok

  defp authorization_digest do
    :sha256 |> :crypto.hash(@authorization) |> Base.encode16(case: :lower)
  end

  defp collect_checkpoints(checkpoints) do
    receive do
      {:reset_checkpoint, checkpoint} -> collect_checkpoints([checkpoint | checkpoints])
    after
      0 -> Enum.reverse(checkpoints)
    end
  end

  defp collect_tagged_messages(tag, messages) do
    receive do
      {^tag, value} -> collect_tagged_messages(tag, [value | messages])
    after
      0 -> Enum.reverse(messages)
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
