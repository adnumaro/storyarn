defmodule Storyarn.Versioning.ProjectSnapshotResetTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Storage.Local
  alias Storyarn.Release
  alias Storyarn.SnapshotResetStorage
  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotReset
  alias Storyarn.Versioning.SnapshotStorage

  @environment "reset-test"
  @authorization String.duplicate("a", 32)
  @retry_authorization String.duplicate("b", 32)

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
    plan_id = plan["plan_id"]
    assert {:ok, ^plan_id} = Ecto.UUID.cast(plan_id)
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

  test "refuses preparation and execution when the lifecycle rollout guard is closed" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})

    assert {:error, :snapshot_reset_rollout_already_applied} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, @environment,
               current_environment: @environment,
               rollout_guard: &deny_post_rollout/1,
               storage_adapter: SnapshotResetStorage
             )

    assert {:ok, plan} = prepare(project.workspace_id)

    assert {:error, :snapshot_reset_rollout_already_applied, ^plan} =
             Versioning.execute_project_snapshot_reset(plan, plan["inventory_digest"],
               current_environment: @environment,
               expected_authorization_digest: authorization_digest(),
               authorization: @authorization,
               rollout_guard: &deny_post_rollout/1,
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

  test "release APIs prepare, execute, and verify an environment-global provider reset" do
    directory = Path.join(System.tmp_dir!(), "storyarn-provider-reset-#{System.unique_integer([:positive])}")
    plan_path = Path.join(directory, "plan.json")
    authorization_path = Path.join(directory, "authorization")
    original_storage = Application.get_env(:storyarn, :storage)
    original_environment = System.get_env("STORYARN_DEPLOYMENT_ENVIRONMENT")
    original_authorization_digest = System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256")

    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    File.write!(authorization_path, @authorization)
    File.chmod!(authorization_path, 0o600)
    Application.put_env(:storyarn, :storage, adapter: SnapshotResetStorage)
    System.put_env("STORYARN_DEPLOYMENT_ENVIRONMENT", @environment)
    System.put_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256", authorization_digest())

    on_exit(fn ->
      File.rm_rf(directory)
      restore_application_env(:storyarn, :storage, original_storage)
      restore_system_env("STORYARN_DEPLOYMENT_ENVIRONMENT", original_environment)
      restore_system_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION_SHA256", original_authorization_digest)
    end)

    if snapshot_lifecycle_rollout_applied?() do
      assert_raise RuntimeError, ~r/snapshot_reset_rollout_already_applied/, fn ->
        Release.prepare_project_snapshot_provider_reset(@environment, plan_path, 10)
      end
    else
      orphan = "projects/900000004/snapshots/project/release-orphan.json.gz"
      :ok = SnapshotResetStorage.put_objects(%{orphan => 10})

      plan = Release.prepare_project_snapshot_provider_reset(@environment, plan_path, 10)
      assert plan["workspace_receipt_ids"] == []
      assert Enum.map(plan["objects"], & &1["key"]) == [orphan]

      completed =
        Release.execute_project_snapshot_provider_reset(
          @environment,
          plan_path,
          plan["inventory_digest"],
          authorization_path
        )

      assert completed["status"] == "completed"
      assert SnapshotResetStorage.objects() == %{}
      assert :ok = Release.verify_project_snapshot_reset_rollout(@environment)
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

  test "does not accept the authorization token from process environment" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)

    previous = System.get_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION")
    System.put_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION", @authorization)

    on_exit(fn ->
      if previous,
        do: System.put_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION", previous),
        else: System.delete_env("STORYARN_SNAPSHOT_RESET_AUTHORIZATION")
    end)

    assert {:error, :snapshot_reset_not_authorized, ^plan} =
             Versioning.execute_project_snapshot_reset(plan, plan["inventory_digest"],
               current_environment: @environment,
               expected_authorization_digest: authorization_digest(),
               rollout_guard: &allow_pre_rollout/1,
               storage_adapter: SnapshotResetStorage
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

  test "the global provider plan deletes orphan snapshot roots without touching current assets" do
    user = user_fixture()
    project = project_fixture(user)
    current_snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    current_key = current_snapshot.manifest_storage_key
    asset_key = "projects/#{project.id}/assets/current/original.png"
    orphan_key = "projects/999999999/snapshots/project/orphan.json.gz"

    :ok =
      SnapshotResetStorage.put_objects(%{
        current_key => current_snapshot.manifest_size_bytes,
        asset_key => 12,
        orphan_key => 24
      })

    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    assert {:ok, provider_plan} = prepare_provider()
    assert provider_plan["scope"] == "provider"
    refute Map.has_key?(provider_plan, "workspace_id")

    assert [[workspace_receipt_id]] =
             Repo.query!(
               "SELECT id FROM project_snapshot_reset_receipts WHERE workspace_id = $1",
               [project.workspace_id]
             ).rows

    assert provider_plan["workspace_receipt_ids"] == [workspace_receipt_id]
    assert provider_plan["scanned_object_count"] == 2
    assert Enum.map(provider_plan["objects"], & &1["key"]) == [orphan_key]

    assert {:ok, provider_completed} = execute_provider(provider_plan)
    assert provider_completed["status"] == "completed"
    assert Map.has_key?(SnapshotResetStorage.objects(), asset_key)
    refute Map.has_key?(SnapshotResetStorage.objects(), orphan_key)
    assert :ok = readiness()
  end

  test "the global provider scan rejects malformed snapshot-looking keys" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    malformed = "projects/not-a-project-id/snapshots/project/orphan.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{malformed => 12})

    assert {:error, :unsafe_snapshot_reset_object} = prepare_provider()
    assert Map.has_key?(SnapshotResetStorage.objects(), malformed)
  end

  test "the global provider scan bounds all inspected objects, including ignored assets" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    assets =
      Map.new(1..3, fn index ->
        {"projects/#{project.id}/assets/#{index}/original.bin", index}
      end)

    :ok = SnapshotResetStorage.put_objects(assets)

    assert {:error, :snapshot_reset_scanned_object_limit_exceeded} =
             prepare_provider(@environment, max_scanned_objects: 2)
  end

  test "the global provider plan checkpoints a failure and resumes with rotated authorization" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    first = "projects/900000001/snapshots/project/first.json.gz"
    second = "projects/900000002/snapshots/project/second.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{first => 10, second => 20})
    assert {:ok, provider_plan} = prepare_provider()
    :ok = SnapshotResetStorage.fail_once([second])

    assert {:error, :snapshot_reset_storage_delete_failed, failed} = execute_provider(provider_plan)
    assert failed["status"] == "failed"

    assert {:ok, completed} =
             execute_provider(failed,
               authorization: @retry_authorization,
               expected_authorization_digest: authorization_digest(@retry_authorization)
             )

    assert completed["status"] == "completed"
    assert SnapshotResetStorage.objects() == %{}
  end

  test "a provider plan rejects workspace receipt drift before deleting" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    orphan = "projects/900000003/snapshots/project/orphan.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{orphan => 10})
    assert {:ok, provider_plan} = prepare_provider()

    other_user = user_fixture()
    other_workspace = Storyarn.Workspaces.get_default_workspace(other_user)
    assert {:ok, other_workspace_plan} = prepare(other_workspace.id)
    assert {:ok, _other_workspace_completed} = execute(other_workspace_plan)

    assert {:error, :snapshot_reset_workspace_receipts_changed, ^provider_plan} =
             execute_provider(provider_plan)

    assert Map.has_key?(SnapshotResetStorage.objects(), orphan)
  end

  test "a provider plan rejects storage namespace drift before deleting" do
    orphan = "projects/900000005/snapshots/project/orphan.json.gz"
    :ok = SnapshotResetStorage.put_objects(%{orphan => 10})
    assert {:ok, provider_plan} = prepare_provider()
    :ok = SnapshotResetStorage.change_namespace_fingerprint()

    assert {:error, :snapshot_reset_storage_namespace_changed, ^provider_plan} =
             execute_provider(provider_plan)

    assert Map.has_key?(SnapshotResetStorage.objects(), orphan)
  end

  test "a local provider plan rejects an upload root retargeted through a symlink before deleting" do
    unique = System.unique_integer([:positive])
    root = Path.expand("test/tmp/snapshot-reset-local-root-#{unique}")
    preserved_root = root <> "-preserved"
    replacement_root = root <> "-replacement"
    original_storage = Application.get_env(:storyarn, :storage)
    orphan = "projects/900000006/snapshots/project/orphan.json.gz"

    Application.put_env(:storyarn, :storage,
      adapter: Local,
      upload_dir: root,
      public_path: "/test-uploads"
    )

    on_exit(fn ->
      restore_application_env(:storyarn, :storage, original_storage)
      File.rm(root)
      File.rm_rf(preserved_root)
      File.rm_rf(replacement_root)
    end)

    assert {:ok, _url} = Local.upload(orphan, "original", "application/octet-stream")

    assert {:ok, provider_plan} =
             prepare_provider(@environment, storage_adapter: Local)

    File.rename!(root, preserved_root)
    replacement_path = Path.join(replacement_root, orphan)
    File.mkdir_p!(Path.dirname(replacement_path))
    File.write!(replacement_path, "replacement")
    assert :ok = File.ln_s(replacement_root, root)

    assert {:error, :snapshot_reset_storage_namespace_unavailable, ^provider_plan} =
             execute_provider(provider_plan, storage_adapter: Local)

    assert File.read!(Path.join(preserved_root, orphan)) == "original"
    assert File.read!(replacement_path) == "replacement"
  end

  test "a local provider plan rejects a different directory at the same upload root before deleting" do
    unique = System.unique_integer([:positive])
    root = Path.expand("test/tmp/snapshot-reset-local-replaced-root-#{unique}")
    preserved_root = root <> "-preserved"
    original_storage = Application.get_env(:storyarn, :storage)
    orphan = "projects/900000007/snapshots/project/orphan.json.gz"

    Application.put_env(:storyarn, :storage,
      adapter: Local,
      upload_dir: root,
      public_path: "/test-uploads"
    )

    on_exit(fn ->
      restore_application_env(:storyarn, :storage, original_storage)
      File.rm_rf(root)
      File.rm_rf(preserved_root)
    end)

    assert {:ok, _url} = Local.upload(orphan, "original", "application/octet-stream")

    assert {:ok, provider_plan} =
             prepare_provider(@environment, storage_adapter: Local)

    File.rename!(root, preserved_root)
    replacement_path = Path.join(root, orphan)
    File.mkdir_p!(Path.dirname(replacement_path))
    File.write!(replacement_path, "replacement")

    assert {:error, :snapshot_reset_storage_namespace_changed, ^provider_plan} =
             execute_provider(provider_plan, storage_adapter: Local)

    assert File.read!(Path.join(preserved_root, orphan)) == "original"
    assert File.read!(replacement_path) == "replacement"
  end

  test "provider preparation rejects workspace receipts from another storage namespace" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(project.workspace_id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)
    :ok = SnapshotResetStorage.change_namespace_fingerprint()

    assert {:error, :snapshot_reset_rollout_receipts_incomplete} = prepare_provider()
  end

  test "rejects an out-of-range attempt count before any delete" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    :ok = SnapshotResetStorage.put_objects(%{snapshot.manifest_storage_key => snapshot.manifest_size_bytes})
    assert {:ok, plan} = prepare(project.workspace_id)

    tampered =
      plan
      |> Map.put("status", "failed")
      |> Map.put("attempt_count", 9_223_372_036_854_775_807)
      |> Map.put("authorization_digest", authorization_digest())
      |> Map.put("last_error_code", "tampered_attempt")

    assert {:error, :invalid_snapshot_reset_plan} = ProjectSnapshotReset.validate_plan(tampered)
    assert {:error, :invalid_snapshot_reset_plan, ^tampered} = execute(tampered)
    assert Repo.get!(ProjectSnapshot, snapshot.id)
    assert Map.has_key?(SnapshotResetStorage.objects(), snapshot.manifest_storage_key)
  end

  test "persists a workspace receipt that rejects mutation" do
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

  test "persists a provider receipt that rejects mutation" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()

    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE project_snapshot_provider_reset_receipts SET object_count = object_count + 1")
    end
  end

  test "workspace receipt history rejects truncation" do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query("TRUNCATE project_snapshot_reset_receipts")
  end

  test "provider receipt history rejects truncation" do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query("TRUNCATE project_snapshot_provider_reset_receipts")
  end

  test "receipt ID vectors reject NULL and duplicate ids" do
    assert [[false, false, false, false, true, true]] =
             Repo.query!("""
             SELECT
               storyarn_valid_sorted_positive_bigints(ARRAY[1, NULL]::bigint[]),
               storyarn_valid_sorted_positive_bigints(ARRAY[1, 1]::bigint[]),
               storyarn_valid_sorted_positive_bigints(ARRAY[2, 1]::bigint[]),
               storyarn_valid_sorted_positive_bigints(ARRAY[0]::bigint[]),
               storyarn_valid_sorted_positive_bigints(ARRAY[]::bigint[]),
               storyarn_valid_sorted_positive_bigints(ARRAY[1, 2]::bigint[])
             """).rows
  end

  test "rollout readiness requires the environment-global provider receipt" do
    assert {:error, :snapshot_reset_rollout_provider_receipt_missing} = readiness()
    assert {:ok, _completed} = complete_provider_reset()
    assert :ok = readiness()
  end

  test "rollout readiness rejects malformed expected and current environments" do
    assert {:error, :snapshot_reset_environment_required} = readiness("invalid environment")

    assert {:error, :snapshot_reset_current_environment_unconfigured} =
             ProjectSnapshotReset.verify_rollout_readiness(@environment,
               current_environment: "invalid environment",
               repo: Repo
             )
  end

  test "rollout readiness rejects a workspace without a receipt" do
    user = user_fixture()
    _project = project_fixture(user)

    assert {:error, :snapshot_reset_rollout_receipts_incomplete} = readiness()
  end

  test "rollout readiness rejects a latest wrong-environment receipt over an older valid one" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()

    assert {:ok, production_plan} =
             Versioning.prepare_project_snapshot_reset(project.workspace_id, "production",
               current_environment: "production",
               rollout_guard: &allow_pre_rollout/1,
               storage_adapter: SnapshotResetStorage
             )

    assert {:ok, _production_completed} =
             Versioning.execute_project_snapshot_reset(
               production_plan,
               production_plan["inventory_digest"],
               current_environment: "production",
               expected_authorization_digest: authorization_digest(),
               authorization: @authorization,
               rollout_guard: &allow_pre_rollout/1,
               storage_adapter: SnapshotResetStorage
             )

    assert {:ok, _provider_completed} = complete_provider_reset("production")
    assert :ok = readiness("production")
    assert {:error, :snapshot_reset_rollout_receipts_incomplete} = readiness()
  end

  test "rollout readiness rejects current project drift after the latest receipt" do
    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    project = project_fixture(user, %{workspace: workspace})
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()

    _new_project = project_fixture(user, %{workspace: workspace})

    assert {:error, :snapshot_reset_rollout_receipts_incomplete} = readiness()
  end

  test "rollout readiness rejects non-empty versioning tables globally" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    _entity_version = entity_version_fixture(project)

    assert {:error, :snapshot_reset_rollout_database_not_empty} = readiness()
  end

  test "rollout readiness rejects non-empty project snapshot rows globally" do
    user = user_fixture()
    project = project_fixture(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, _completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    _snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    assert {:error, :snapshot_reset_rollout_database_not_empty} = readiness()
  end

  test "rollout readiness fails closed on an invalid repository response" do
    assert {:error, :snapshot_reset_rollout_readiness_invalid_response} =
             readiness(@environment, repo: Storyarn.InvalidSnapshotResetRepo)
  end

  test "a project scope A-B-A appends a revision for every newly prepared plan" do
    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    project = project_fixture(user, %{workspace: workspace})
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, plan} = prepare(project.workspace_id)
    assert {:ok, first_completed} = execute(plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    new_project = project_fixture(user, %{workspace: workspace})
    assert {:ok, changed_scope_plan} = prepare(project.workspace_id)

    assert {:ok, second_completed} =
             execute(changed_scope_plan,
               authorization: @retry_authorization,
               expected_authorization_digest: authorization_digest(@retry_authorization)
             )

    assert {:error, :snapshot_reset_rollout_provider_receipt_missing} = readiness()
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()
    assert {:ok, deleted_project} = Storyarn.Projects.delete_project(new_project, user.id)
    assert {:ok, _deleted_project} = Storyarn.Projects.permanently_delete_project(deleted_project)
    assert {:error, :snapshot_reset_rollout_receipts_incomplete} = readiness()
    assert {:ok, returned_scope_plan} = prepare(project.workspace_id)
    assert {:ok, third_completed} = execute(returned_scope_plan)
    assert {:error, :snapshot_reset_rollout_provider_receipt_missing} = readiness()
    assert {:ok, _provider_completed} = complete_provider_reset()

    assert first_completed["inventory_digest"] != second_completed["inventory_digest"]
    assert first_completed["inventory_digest"] != third_completed["inventory_digest"]
    assert first_completed["plan_id"] != third_completed["plan_id"]
    assert :ok = readiness()

    assert [[first_projects], [second_projects], [third_projects]] =
             Repo.query!(
               """
               SELECT project_ids
               FROM project_snapshot_reset_receipts
               WHERE workspace_id = $1
               ORDER BY id
               """,
               [workspace.id]
             ).rows

    assert first_projects == [project.id]
    assert second_projects == Enum.sort([project.id, new_project.id])
    assert third_projects == [project.id]
  end

  test "a workspace added after the global sweep invalidates its receipt frontier" do
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()

    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(workspace.id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)

    assert {:error, :snapshot_reset_rollout_provider_receipt_missing} = readiness()
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()
  end

  test "a workspace removed after the global sweep invalidates its receipt frontier" do
    user = user_fixture()
    workspace = Storyarn.Workspaces.get_default_workspace(user)
    :ok = SnapshotResetStorage.put_objects(%{})
    assert {:ok, workspace_plan} = prepare(workspace.id)
    assert {:ok, _workspace_completed} = execute(workspace_plan)
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()

    assert {:ok, _deleted_workspace} = Storyarn.Workspaces.delete_workspace(workspace)

    assert {:error, :snapshot_reset_rollout_provider_receipt_missing} = readiness()
    assert {:ok, _provider_completed} = complete_provider_reset()
    assert :ok = readiness()
  end

  test "a conflicting receipt fails before provider or database deletion" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    :ok =
      SnapshotResetStorage.put_objects(%{
        snapshot.project_storage_key => snapshot.project_size_bytes,
        snapshot.manifest_storage_key => snapshot.manifest_size_bytes
      })

    assert {:ok, plan} = prepare(project.workspace_id)

    Repo.query!(
      """
      INSERT INTO project_snapshot_reset_receipts (
        workspace_id, plan_id, project_ids, environment, inventory_digest,
        database_inventory_digest, storage_namespace_fingerprint,
        authorization_digest, object_count,
        object_bytes, snapshot_row_count, entity_version_row_count,
        attempt_count, completed_at
      )
      VALUES ($1, $2::text::uuid, $3, 'conflicting-environment', $4, $5, $6, $7, $8, $9, $10, $11, 1, $12)
      """,
      [
        project.workspace_id,
        plan["plan_id"],
        plan["project_ids"],
        plan["inventory_digest"],
        plan["database_inventory_digest"],
        plan["storage_namespace_fingerprint"],
        authorization_digest(),
        length(plan["objects"]),
        Enum.sum(Enum.map(plan["objects"], & &1["size"])),
        length(plan["snapshot_row_ids"]),
        length(plan["entity_version_row_ids"]),
        Storyarn.Shared.TimeHelpers.now()
      ]
    )

    assert {:error, :snapshot_reset_receipt_mismatch, ^plan} = execute(plan)
    assert Repo.get!(ProjectSnapshot, snapshot.id)
    assert map_size(SnapshotResetStorage.objects()) == 2
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

    assert {:ok, recovered} =
             execute(stale_plan,
               authorization: @retry_authorization,
               expected_authorization_digest: authorization_digest(@retry_authorization)
             )

    assert recovered["status"] == "completed"
    assert recovered["authorization_digest"] == completed["authorization_digest"]
    assert recovered["attempt_count"] == completed["attempt_count"]
    assert recovered["completed_at"] == completed["completed_at"]

    assert [[receipt_authorization_digest, receipt_attempt_count, receipt_completed_at]] =
             Repo.query!(
               """
               SELECT authorization_digest, attempt_count, completed_at
               FROM project_snapshot_reset_receipts
               WHERE workspace_id = $1
               """,
               [project.workspace_id]
             ).rows

    assert receipt_authorization_digest == completed["authorization_digest"]
    assert receipt_attempt_count == completed["attempt_count"]
    assert DateTime.to_iso8601(DateTime.from_naive!(receipt_completed_at, "Etc/UTC")) == completed["completed_at"]

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

    assert {:error, :invalid_snapshot_reset_plan} =
             plan
             |> Map.put("environment", <<0xFF>>)
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

  defp prepare_provider(environment \\ @environment, opts \\ []) do
    defaults = [
      current_environment: environment,
      rollout_guard: &allow_pre_rollout/1,
      storage_adapter: SnapshotResetStorage
    ]

    ProjectSnapshotReset.prepare_provider(environment, Keyword.merge(defaults, opts))
  end

  defp execute_provider(plan, opts \\ []) do
    defaults = [
      current_environment: plan["environment"],
      expected_authorization_digest: authorization_digest(),
      authorization: @authorization,
      rollout_guard: &allow_pre_rollout/1,
      storage_adapter: SnapshotResetStorage
    ]

    ProjectSnapshotReset.execute(
      plan,
      plan["inventory_digest"],
      Keyword.merge(defaults, opts)
    )
  end

  defp complete_provider_reset(environment \\ @environment) do
    with {:ok, plan} <- prepare_provider(environment) do
      execute_provider(plan)
    end
  end

  defp readiness(environment \\ @environment, opts \\ []) do
    ProjectSnapshotReset.verify_rollout_readiness(
      environment,
      Keyword.merge(
        [current_environment: environment, repo: Repo, storage_adapter: SnapshotResetStorage],
        opts
      )
    )
  end

  defp allow_pre_rollout(_repo), do: :ok

  defp deny_post_rollout(_repo), do: {:error, :snapshot_reset_rollout_already_applied}

  defp snapshot_lifecycle_rollout_applied? do
    %{rows: [[applied?]]} =
      Repo.query!("SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version >= $1)", [20_260_805_130_000])

    applied?
  end

  defp authorization_digest(authorization \\ @authorization) do
    :sha256 |> :crypto.hash(authorization) |> Base.encode16(case: :lower)
  end

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

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
