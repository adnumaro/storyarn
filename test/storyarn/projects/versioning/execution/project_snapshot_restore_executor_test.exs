alias Storyarn.Accounts.User
alias Storyarn.Platform.ObjectStorage.Adapters.Local
alias Storyarn.Projects.Assets
alias Storyarn.Projects.Assets.Asset
alias Storyarn.Projects.Assets.BlobStore
alias Storyarn.Projects.Assets.Storage
alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
alias Storyarn.Scenes
alias Storyarn.Scenes.Scene

defmodule Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutorTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Platform.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References.EntityReference
  alias Storyarn.Projects.References.RichTextMentions
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Projects.Versioning.ProjectSnapshotAssetMaterializer.Plan, as: AssetPlan
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutor
  alias Storyarn.Projects.Versioning.ProjectSnapshotZip
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  defmodule EmptyArchiveReader do
    @moduledoc false
    def verify(_snapshot) do
      {:ok,
       %{
         manifest: %{"assets" => [], "objects" => [%{"kind" => "project"}]},
         project: Process.get({__MODULE__, :project_object})
       }}
    end
  end

  defmodule SingleBlobArchiveReader do
    @moduledoc false

    @bytes "failed restore staging bytes"
    @path "blobs/failed-restore-staging.bin"

    def verify(_snapshot) do
      {:ok,
       %{
         manifest: %{
           "assets" => [],
           "objects" => [
             %{
               "kind" => "asset_blob",
               "path" => @path,
               "size_bytes" => byte_size(@bytes),
               "sha256" => sha256(@bytes),
               "content_type" => "application/octet-stream"
             }
           ]
         },
         project: Process.get({EmptyArchiveReader, :project_object})
       }}
    end

    def stream_entry(_plan, @path), do: {:ok, [{:ok, @bytes}]}
    def path, do: @path

    defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
  end

  defmodule FailingMaterializer do
    @moduledoc false

    def prepare(project_id, restore_id, manifest, _project, prefix, _keys) do
      logical_bytes =
        manifest["objects"]
        |> Enum.filter(&(&1["kind"] == "asset_blob"))
        |> Enum.sum_by(& &1["size_bytes"])

      {:ok,
       %AssetPlan{
         project_id: project_id,
         restore_identity: to_string(restore_id),
         staging_prefix: prefix,
         assets: [],
         blobs: [],
         source_refs: %{},
         logical_bytes: logical_bytes,
         staging_bytes: logical_bytes
       }}
    end

    def stage_destination_objects(_plan, _tracker), do: {:error, :injected_destination_failure}
    def adopt_locked(_plan, _project, _actor, _tracker), do: {:error, :unexpected_adoption}
    def verify_adopted_locked(_plan, _map), do: {:error, :unexpected_postverify}
  end

  defmodule EmptyMaterializer do
    @moduledoc false

    def prepare(project_id, restore_id, _manifest, _project, prefix, _keys) do
      {:ok,
       %AssetPlan{
         project_id: project_id,
         restore_identity: to_string(restore_id),
         staging_prefix: prefix,
         assets: [],
         blobs: [],
         source_refs: %{},
         logical_bytes: 0,
         staging_bytes: 0
       }}
    end

    def stage_destination_objects(_plan, _tracker), do: :ok

    def adopt_locked(_plan, _project, _actor, _tracker) do
      {:ok, %{assets: [], logical_id_map: %{}, source_id_map: %{}}}
    end

    def verify_adopted_locked(_plan, _map), do: :ok
  end

  defmodule CountingEmptyMaterializer do
    @moduledoc false
    alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutorTest.EmptyMaterializer

    def prepare(project_id, restore_id, manifest, project, prefix, keys) do
      EmptyMaterializer.prepare(project_id, restore_id, manifest, project, prefix, keys)
    end

    def stage_destination_objects(plan, tracker) do
      Process.put({__MODULE__, :stage_count}, Process.get({__MODULE__, :stage_count}, 0) + 1)
      EmptyMaterializer.stage_destination_objects(plan, tracker)
    end

    def adopt_locked(plan, project, actor, tracker), do: EmptyMaterializer.adopt_locked(plan, project, actor, tracker)

    def verify_adopted_locked(plan, map), do: EmptyMaterializer.verify_adopted_locked(plan, map)
  end

  defmodule PrepareSpyMaterializer do
    @moduledoc false

    def prepare(_project_id, _restore_id, _manifest, _project, _prefix, _keys) do
      Process.put({__MODULE__, :called}, true)
      {:error, :unexpected_materializer_prepare}
    end
  end

  defmodule ErrorArchiveReader do
    @moduledoc false
    def verify(_snapshot), do: {:error, Process.get({__MODULE__, :reason})}
  end

  defmodule OversizedMaterializer do
    @moduledoc false

    def prepare(project_id, restore_id, _manifest, _project, prefix, _keys) do
      {:ok,
       %AssetPlan{
         project_id: project_id,
         restore_identity: to_string(restore_id),
         staging_prefix: prefix,
         assets: [],
         blobs: [],
         source_refs: %{},
         logical_bytes: 1_000_000_000_000,
         staging_bytes: 0
       }}
    end

    def stage_destination_objects(_plan, _tracker) do
      Process.put({__MODULE__, :staged}, true)
      {:error, :unexpected_capacity_staging}
    end
  end

  defmodule AcceptingRecovery do
    @moduledoc false
    def validate_materialization_snapshot(_project), do: :ok

    def lock_materializable_localization_actors(_project, opts) do
      {:ok, MapSet.new(Keyword.fetch!(opts, :required_actor_ids))}
    end

    def materialize_into_project(_project, _snapshot, _actor, _source_ids, _opts),
      do: {:error, :unexpected_materialization}
  end

  setup do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})
    scope = user_scope_fixture(user)

    assert {:ok, requested} =
             Versioning.request_project_snapshot_restore(scope, project, snapshot, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.oban_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, {:claimed, restore}} =
             Versioning.claim_project_snapshot_restore(requested.id, 1,
               job_id: job.id,
               attempt: 1
             )

    project_object = empty_project_object(project)
    Process.put({EmptyArchiveReader, :project_object}, project_object)
    on_exit(fn -> Process.delete({EmptyArchiveReader, :project_object}) end)

    %{restore: restore, snapshot: snapshot, project_object: project_object}
  end

  test "a failed attempt durably releases its reservation and the next attempt rotates the lease", context do
    job = Repo.get!(Oban.Job, context.restore.oban_job_id)

    assert {:retry, :injected_destination_failure} =
             Versioning.perform_project_snapshot_restore(context.restore.id, 1,
               job_id: job.id,
               attempt: 1,
               max_attempts: 3,
               executor: fn claimed, _opts ->
                 run_to_injected_failure(claimed, context.snapshot)
               end
             )

    failed_attempt = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert failed_attempt.status == "retrying"
    first_reservation = Repo.get!(StorageReservation, failed_attempt.storage_reservation_id)
    assert first_reservation.status == "released"

    job =
      job
      |> Ecto.Changeset.change(attempt: 2, attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}})
      |> Repo.update!()

    assert {:retry, :injected_destination_failure} =
             Versioning.perform_project_snapshot_restore(failed_attempt.id, 1,
               job_id: job.id,
               attempt: 2,
               max_attempts: 3,
               executor: fn claimed, _opts ->
                 run_to_injected_failure(claimed, context.snapshot)
               end
             )

    second_restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert second_restore.status == "retrying"
    second_reservation = Repo.get!(StorageReservation, second_restore.storage_reservation_id)
    assert second_reservation.id != first_reservation.id
    assert second_reservation.lease_token != first_reservation.lease_token
    assert second_reservation.status == "released"
  end

  test "failure to establish cleanup/release ownership snoozes even on a final delivery", context do
    assert {:snooze, 30} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: reader(context.snapshot),
               asset_materializer: FailingMaterializer,
               project_recovery: AcceptingRecovery,
               cleanup_after_rollback: fn _tracker -> {:error, :cleanup_unavailable} end,
               release_reservation: fn _restore, _context -> {:error, :release_unavailable} end,
               attempt: 5,
               max_attempts: 5
             )

    restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    reservation = Repo.get!(StorageReservation, restore.storage_reservation_id)
    assert restore.status == "running"
    assert reservation.status == "active"
  end

  test "a failed restore deletes staged bytes inline before releasing its reservation", context do
    assert {:retry, :injected_destination_failure} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: SingleBlobArchiveReader,
               asset_materializer: FailingMaterializer,
               project_recovery: AcceptingRecovery
             )

    restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    reservation = Repo.get!(StorageReservation, restore.storage_reservation_id)
    staging_key = reservation.storage_namespace <> "/" <> SingleBlobArchiveReader.path()

    assert reservation.status == "released"
    assert {:error, :enoent} = Storage.download(staging_key)
  end

  test "canonical project fields are mandatory before reservation or storage writes", context do
    project_before = Repo.get!(Project, context.restore.project_id)

    for required_key <- ["name", "settings", "auto_version_flows"] do
      invalid_object = update_in(context.project_object, ["project"], &Map.delete(&1, required_key))
      Process.put({EmptyArchiveReader, :project_object}, invalid_object)

      assert {:error, :invalid_project_snapshot_project_fields} =
               ProjectSnapshotRestoreExecutor.execute(context.restore,
                 archive_reader: EmptyArchiveReader,
                 asset_materializer: EmptyMaterializer,
                 project_recovery: ProjectRecovery
               )

      restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
      assert restore.status == "running"
      assert is_nil(restore.storage_reservation_id)
      assert Repo.get!(Project, project_before.id) == project_before
    end

    for {field, invalid_value} <- [
          {"name", nil},
          {"description", 123},
          {"project_type", %{}},
          {"settings", []},
          {"auto_version_flows", "true"}
        ] do
      invalid_object = put_in(context.project_object, ["project", field], invalid_value)
      Process.put({EmptyArchiveReader, :project_object}, invalid_object)

      assert {:error, :invalid_project_snapshot_project_fields} =
               ProjectSnapshotRestoreExecutor.execute(context.restore,
                 archive_reader: EmptyArchiveReader,
                 asset_materializer: EmptyMaterializer,
                 project_recovery: ProjectRecovery
               )

      restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
      assert restore.status == "running"
      assert is_nil(restore.storage_reservation_id)
      assert Repo.get!(Project, project_before.id) == project_before
    end
  end

  test "postverification failure rolls the final database transaction back", context do
    project = Repo.get!(Project, context.restore.project_id)
    old_sheet = sheet_fixture(project, %{name: "Current graph must survive rollback"})

    assert {:retry, {:project_snapshot_restore_count_mismatch, SheetRecord, 0, 1}} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery,
               before_postverify: fn ->
                 _injected = sheet_fixture(project, %{name: "Injected postverify mismatch"})
                 :ok
               end
             )

    assert is_nil(Repo.get!(Sheet, old_sheet.id).deleted_at)

    refute Repo.exists?(
             from sheet in Sheet,
               where:
                 sheet.project_id == ^project.id and
                   sheet.name == "Injected postverify mismatch"
           )

    restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    reservation = Repo.get!(StorageReservation, restore.storage_reservation_id)
    assert restore.status == "running"
    assert reservation.status == "released"
    assert reservation.cleanup_status == "not_required"
  end

  test "exact restore postverifies null and FK-safe authored references", context do
    project = Repo.get!(Project, context.restore.project_id)
    null_sheet = sheet_fixture(project, %{name: "Authored null inheritance state"})
    stale_sheet = sheet_fixture(project, %{name: "Physically retained stale parent"})
    authored_sheet = sheet_fixture(project, %{name: "Authored residual references"})
    source_sheet = sheet_fixture(project, %{name: "Inheritance source owner"})
    stale_block = block_fixture(source_sheet, %{type: "text", value: %{"content" => "Stale parent"}})
    inherited_block = block_fixture(authored_sheet, %{type: "text", value: %{"content" => "Child"}})
    dangling_block_id = 1_700_000_000 + rem(System.unique_integer([:positive]), 100_000_000)
    flow = flow_fixture(project, %{name: "Authored residual parent flow"})

    assert {:ok, stale_sequence} =
             Storyarn.Flows.create_sequence(flow.id, %{
               "name" => "Physically retained stale sequence",
               "width" => 400.0,
               "height" => 240.0
             })

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Residual speaker", "responses" => []}
      })

    now = TimeHelpers.now()

    assert {1, nil} =
             Repo.update_all(
               from(current in Sheet, where: current.id == ^null_sheet.id),
               set: [hidden_inherited_block_ids: nil]
             )

    assert {1, nil} =
             Repo.update_all(
               from(current in Sheet, where: current.id == ^authored_sheet.id),
               set: [parent_id: stale_sheet.id, hidden_inherited_block_ids: [dangling_block_id]]
             )

    assert {1, nil} =
             Repo.update_all(
               from(current in Block, where: current.id == ^inherited_block.id),
               set: [inherited_from_block_id: stale_block.id]
             )

    assert {1, nil} =
             Repo.update_all(
               from(current in Sheet, where: current.id == ^stale_sheet.id),
               set: [deleted_at: now]
             )

    assert {1, nil} =
             Repo.update_all(
               from(current in Block, where: current.id == ^stale_block.id),
               set: [deleted_at: now]
             )

    assert {1, nil} =
             Repo.update_all(
               from(current in FlowNode, where: current.id == ^stale_sequence.id),
               set: [deleted_at: now]
             )

    # The soft-delete trigger reparents current children. Reapply the authored
    # FK-safe residual state after archival so capture must preserve it.
    assert {1, nil} =
             Repo.update_all(
               from(current in FlowNode, where: current.id == ^dialogue.id),
               set: [parent_id: stale_sequence.id]
             )

    _source_language = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    speaker_text =
      localized_text_fixture(project.id, %{
        source_type: "flow_node",
        source_id: dialogue.id,
        source_field: "text",
        source_text: "Residual speaker",
        locale_code: "es"
      })

    assert {1, nil} =
             Repo.update_all(
               from(text in LocalizedText, where: text.id == ^speaker_text.id),
               set: [speaker_sheet_id: stale_sheet.id]
             )

    target_object = project.id |> capture_project_object() |> Map.put("asset_catalog_refs", %{})

    target_sheets = Map.new(target_object["sheets"], &{&1["snapshot"]["name"], &1["snapshot"]})
    assert target_sheets[null_sheet.name]["hidden_inherited_block_ids"] == nil
    assert target_sheets[authored_sheet.name]["hidden_inherited_block_ids"] == [dangling_block_id]
    assert target_sheets[authored_sheet.name]["parent_id"] == nil

    assert Enum.find(target_object["tree"]["sheets"], &(&1["id"] == authored_sheet.id))["parent_id"] ==
             stale_sheet.id

    assert Enum.find(target_sheets[authored_sheet.name]["blocks"], &(&1["original_id"] == inherited_block.id))[
             "inherited_from_block_id"
           ] == stale_block.id

    target_flow = Enum.find(target_object["flows"], &(&1["id"] == flow.id))["snapshot"]
    assert Enum.find(target_flow["nodes"], &(&1["original_id"] == dialogue.id))["parent_id"] == stale_sequence.id

    assert Enum.find(target_object["localization"]["texts"], fn text ->
             text["source_type"] == "flow_node" and text["source_id"] == dialogue.id and
               text["source_field"] == "text" and text["locale_code"] == "es"
           end)["speaker_sheet_id"] == stale_sheet.id

    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {1, nil} =
             Repo.update_all(
               from(current in Sheet, where: current.id == ^authored_sheet.id),
               set: [parent_id: nil]
             )

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_sheets =
      Repo.all(from restored in Sheet, where: restored.project_id == ^project.id and is_nil(restored.deleted_at))

    restored_null = Enum.find(restored_sheets, &(&1.name == null_sheet.name))
    restored_authored = Enum.find(restored_sheets, &(&1.name == authored_sheet.name))
    assert restored_null.hidden_inherited_block_ids == nil
    assert restored_authored.hidden_inherited_block_ids == [dangling_block_id]
    assert restored_authored.parent_id == stale_sheet.id

    restored_block =
      Repo.one!(
        from block in Block,
          where: block.sheet_id == ^restored_authored.id and is_nil(block.deleted_at)
      )

    assert restored_block.inherited_from_block_id == stale_block.id

    restored_flow =
      Repo.one!(from current in Flow, where: current.project_id == ^project.id and is_nil(current.deleted_at))

    restored_dialogue =
      Repo.one!(
        from node in FlowNode,
          where: node.flow_id == ^restored_flow.id and is_nil(node.deleted_at) and node.type == "dialogue"
      )

    assert restored_dialogue.parent_id == stale_sequence.id

    assert Repo.exists?(
             from text in LocalizedText,
               where:
                 text.project_id == ^project.id and is_nil(text.archived_at) and
                   text.source_type == "flow_node" and text.source_id == ^restored_dialogue.id and
                   text.source_field == "text" and text.locale_code == "es" and
                   text.speaker_sheet_id == ^stale_sheet.id
           )

    assert Repo.get!(ProjectSnapshotRestore, context.restore.id).status == "completed"
  end

  test "archive availability and integrity failures stop before reservation or mutation", context do
    project = Repo.get!(Project, context.restore.project_id)
    current_sheet = sheet_fixture(project, %{name: "Archive failure sentinel"})

    for reason <- [:snapshot_archive_not_found, {:snapshot_zip_entry_checksum_mismatch, "project.json"}] do
      Process.put({ErrorArchiveReader, :reason}, reason)
      Process.delete({PrepareSpyMaterializer, :called})

      assert {:error, ^reason} =
               ProjectSnapshotRestoreExecutor.execute(context.restore,
                 archive_reader: ErrorArchiveReader,
                 asset_materializer: PrepareSpyMaterializer,
                 project_recovery: ProjectRecovery
               )

      refute Process.get({PrepareSpyMaterializer, :called})
      assert is_nil(Repo.get!(Sheet, current_sheet.id).deleted_at)
      assert is_nil(Repo.get!(ProjectSnapshotRestore, context.restore.id).storage_reservation_id)
    end
  end

  test "asset materializer preflight uses the exact-only API", context do
    Process.delete({PrepareSpyMaterializer, :called})

    assert {:error, :unexpected_materializer_prepare} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: PrepareSpyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert Process.get({PrepareSpyMaterializer, :called})
  end

  test "a transient archive read failure retries through the lifecycle", context do
    Process.put({ErrorArchiveReader, :reason}, %Req.TransportError{reason: :timeout})
    job = Repo.get!(Oban.Job, context.restore.oban_job_id)

    assert {:retry, :snapshot_archive_storage_unavailable} =
             Versioning.perform_project_snapshot_restore(context.restore.id, 1,
               job_id: job.id,
               attempt: 1,
               max_attempts: 3,
               executor: fn claimed, _opts ->
                 ProjectSnapshotRestoreExecutor.execute(claimed,
                   archive_reader: ErrorArchiveReader,
                   asset_materializer: PrepareSpyMaterializer,
                   project_recovery: ProjectRecovery
                 )
               end
             )

    retried = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert retried.status == "retrying"
    assert retried.failure_code == "snapshot_archive_storage_unavailable"
    assert is_nil(retried.storage_reservation_id)
  end

  test "archive integrity failures remain terminal through the lifecycle", context do
    reason = {:snapshot_zip_entry_checksum_mismatch, "project.json"}
    Process.put({ErrorArchiveReader, :reason}, reason)
    job = Repo.get!(Oban.Job, context.restore.oban_job_id)

    assert {:discard, :snapshot_zip_entry_checksum_mismatch} =
             Versioning.perform_project_snapshot_restore(context.restore.id, 1,
               job_id: job.id,
               attempt: 1,
               max_attempts: 3,
               executor: fn claimed, _opts ->
                 ProjectSnapshotRestoreExecutor.execute(claimed,
                   archive_reader: ErrorArchiveReader,
                   asset_materializer: PrepareSpyMaterializer,
                   project_recovery: ProjectRecovery
                 )
               end
             )

    failed = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert failed.status == "failed"
    assert failed.failure_code == "snapshot_zip_entry_checksum_mismatch"
    assert is_nil(failed.storage_reservation_id)
  end

  test "a transient archive failure terminalizes only after the delivery budget is exhausted", context do
    Process.put({ErrorArchiveReader, :reason}, {:http_error, 503, "unavailable"})
    job = Repo.get!(Oban.Job, context.restore.oban_job_id)

    assert {:discard, :snapshot_archive_storage_unavailable} =
             Versioning.perform_project_snapshot_restore(context.restore.id, 1,
               job_id: job.id,
               attempt: 1,
               max_attempts: 1,
               executor: fn claimed, _opts ->
                 ProjectSnapshotRestoreExecutor.execute(claimed,
                   archive_reader: ErrorArchiveReader,
                   asset_materializer: PrepareSpyMaterializer,
                   project_recovery: ProjectRecovery
                 )
               end
             )

    failed = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert failed.status == "failed"
    assert failed.failure_code == "snapshot_archive_storage_unavailable"
    assert is_nil(failed.storage_reservation_id)
  end

  test "capacity rejection happens before provider or database writes", context do
    project = Repo.get!(Project, context.restore.project_id)
    current_sheet = sheet_fixture(project, %{name: "Capacity sentinel"})
    Process.delete({OversizedMaterializer, :staged})

    assert {:retry, {:limit_reached, details}} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: OversizedMaterializer,
               project_recovery: ProjectRecovery
             )

    assert details.resource == :storage_bytes_per_workspace
    refute Process.get({OversizedMaterializer, :staged})
    assert is_nil(Repo.get!(Sheet, current_sheet.id).deleted_at)
    assert is_nil(Repo.get!(ProjectSnapshotRestore, context.restore.id).storage_reservation_id)
  end

  test "asset trash failure rolls back graph trash and releases storage ownership", context do
    project = Repo.get!(Project, context.restore.project_id)
    current_sheet = sheet_fixture(project, %{name: "Asset trash rollback sentinel"})
    actor = Repo.get!(User, context.restore.requested_by_id)
    current_asset = image_asset_fixture(project, actor)

    assert {:retry, :injected_asset_trash_failure} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery,
               trash_active_assets: fn previous, actor_id ->
                 assert previous.asset_ids == [current_asset.id]
                 assert actor_id == context.restore.requested_by_id
                 {:error, :injected_asset_trash_failure}
               end
             )

    assert is_nil(Repo.get!(Sheet, current_sheet.id).deleted_at)
    assert is_nil(Repo.get!(Asset, current_asset.id).deleted_at)
    restore = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    assert Repo.get!(StorageReservation, restore.storage_reservation_id).status == "released"
  end

  test "a duplicate delivery replays the completed semantic receipt without new ownership", context do
    assert {:ok, first} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    completed = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    reservation_count = Repo.aggregate(StorageReservation, :count, :id)

    assert {:ok, replayed} = ProjectSnapshotRestoreExecutor.execute(completed, [])
    assert replayed == first
    assert Repo.aggregate(StorageReservation, :count, :id) == reservation_count
  end

  test "commits one exact graph while preserving prior trash, localization, and runtime indexes", context do
    project = Repo.get!(Project, context.restore.project_id)

    _source_language =
      source_language_fixture(project, %{locale_code: "en", name: "English"})

    _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    archived_language = language_fixture(project, %{locale_code: "fr", name: "French"})
    assert {:ok, _archived_language} = Localization.remove_language(archived_language)
    archived_language_before = Repo.get!(ProjectLanguage, archived_language.id)

    sheet = sheet_fixture(project, %{name: "Target character"})

    block =
      block_fixture(sheet, %{
        type: "rich_text",
        config: %{"label" => "mood", "placeholder" => ""},
        value: %{"content" => "calm"}
      })

    flow = flow_fixture(project, %{name: "Target dialogue"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Hello",
          "speaker_sheet_id" => sheet.id,
          "responses" => [%{"id" => "continue", "text" => "Continue"}]
        }
      })

    scene = scene_fixture(project, %{name: "Target map"})
    _layer = layer_fixture(scene, %{"name" => "Foreground"})
    _pin = pin_fixture(scene, %{"label" => "Gate"})
    _zone = zone_fixture(scene, %{"name" => "Courtyard"})

    assert {:ok, _glossary} =
             Localization.create_glossary_entry(project, %{
               source_term: "Dragon",
               source_locale: "en",
               target_term: "Dragón",
               target_locale: "es",
               context: "Creature"
             })

    dialogue_text =
      Localization.get_text_by_source("flow_node", dialogue.id, "text", "es")

    assert {:ok, dialogue_text} =
             Localization.update_text(dialogue_text, %{
               translated_text: "Hola",
               status: "final",
               translator_notes: "Exact target dialogue"
             })

    target_object = active_project_object(project.id)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    old_entity_ref =
      %EntityReference{}
      |> EntityReference.changeset(%{
        source_type: "flow_node",
        source_id: dialogue.id,
        target_type: "sheet",
        target_id: sheet.id,
        context: "pre-restore recovery sentinel"
      })
      |> Repo.insert!()

    old_variable_ref =
      %VariableReference{}
      |> VariableReference.changeset(%{
        source_type: "flow_node",
        source_id: dialogue.id,
        flow_node_id: dialogue.id,
        block_id: block.id,
        kind: "read",
        source_sheet: sheet.name,
        source_variable: "mood"
      })
      |> Repo.insert!()

    pretrash_flow = flow_fixture(project, %{name: "Already trashed"})
    pretrash_node = node_fixture(pretrash_flow, %{type: "dialogue", data: %{"text" => "Old trash"}})
    pretrash_at = DateTime.add(TimeHelpers.now(), -3_600, :second)

    Repo.update_all(
      from(node in FlowNode, where: node.flow_id == ^pretrash_flow.id),
      set: [deleted_at: pretrash_at, updated_at: pretrash_at]
    )

    Repo.update_all(
      from(row in Flow, where: row.id == ^pretrash_flow.id),
      set: [deleted_at: pretrash_at, updated_at: pretrash_at]
    )

    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project.id and text.source_type == "flow_node" and
            text.source_id == ^pretrash_node.id
      ),
      set: [archived_at: pretrash_at, archive_reason: "source_deleted", updated_at: pretrash_at]
    )

    pretrash_flow_before = Repo.get!(Flow, pretrash_flow.id)
    pretrash_node_before = Repo.get!(FlowNode, pretrash_node.id)

    pretrash_text_before =
      Repo.one!(
        from text in LocalizedText,
          where:
            text.project_id == ^project.id and text.source_type == "flow_node" and
              text.source_id == ^pretrash_node.id,
          limit: 1
      )

    pretrash_ref =
      %EntityReference{}
      |> EntityReference.changeset(%{
        source_type: "flow_node",
        source_id: pretrash_node.id,
        target_type: "sheet",
        target_id: sheet.id,
        context: "pre-existing trash reference"
      })
      |> Repo.insert!()

    orphan_text =
      localized_text_fixture(project.id, %{
        source_type: "flow_node",
        source_id: 1_500_000_000 + rem(System.unique_integer([:positive]), 100_000_000),
        source_field: "text",
        source_text: "Orphan current localization",
        locale_code: "es"
      })

    project
    |> Project.update_changeset(%{
      "name" => "Current state to replace",
      "settings" => Map.put(project.settings, "restore_probe", true),
      "auto_version_flows" => not project.auto_version_flows
    })
    |> Repo.update!()

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    completed = Repo.get!(ProjectSnapshotRestore, context.restore.id)
    reservation = Repo.get!(StorageReservation, result.reservation_id)
    assert completed.status == "completed"
    assert completed.phase == "completed"
    assert completed.result_digest == result.result_digest
    assert reservation.status == "committed"
    assert result.content_replaced
    assert sheet.id in result.replaced_sheet_ids
    assert flow.id in result.replaced_flow_ids
    assert scene.id in result.replaced_scene_ids

    restored_project = Repo.get!(Project, project.id)
    assert restored_project.name == target_object["project"]["name"]
    assert restored_project.settings == target_object["project"]["settings"]
    assert restored_project.auto_version_flows == target_object["project"]["auto_version_flows"]

    assert Repo.get!(Flow, flow.id).deleted_at
    assert Repo.get!(Sheet, sheet.id).deleted_at
    assert Repo.get!(Scene, scene.id).deleted_at
    assert Repo.get!(LocalizedText, dialogue_text.id).archived_at
    assert Repo.get!(LocalizedText, dialogue_text.id).translator_notes == "Exact target dialogue"

    archived_orphan = Repo.get!(LocalizedText, orphan_text.id)
    assert archived_orphan.archived_at
    assert archived_orphan.archive_reason == "version_replaced"

    assert Repo.get!(ProjectLanguage, archived_language.id) == archived_language_before
    assert Repo.get!(Flow, pretrash_flow.id) == pretrash_flow_before
    assert Repo.get!(FlowNode, pretrash_node.id) == pretrash_node_before
    assert Repo.get!(LocalizedText, pretrash_text_before.id) == pretrash_text_before
    assert Repo.get!(EntityReference, pretrash_ref.id) == pretrash_ref
    assert Repo.get!(EntityReference, old_entity_ref.id) == old_entity_ref
    assert Repo.get!(VariableReference, old_variable_ref.id) == old_variable_ref

    assert Enum.sort(
             Repo.all(
               from language in ProjectLanguage,
                 where: language.project_id == ^project.id and is_nil(language.archived_at),
                 select: language.locale_code
             )
           ) == ["en", "es"]

    assert Repo.exists?(
             from text in LocalizedText,
               where:
                 text.project_id == ^project.id and is_nil(text.archived_at) and
                   text.source_type == "flow_node" and text.source_field == "text" and
                   text.translated_text == "Hola" and text.translator_notes == "Exact target dialogue"
           )

    restored_object = active_project_object(project.id)
    assert restored_object["entity_counts"] == target_object["entity_counts"]
    assert restored_object["project"] == target_object["project"]
    assert restored_object["localization"]["glossary"] == target_object["localization"]["glossary"]
  end

  test "exact restore preserves existing localization actors and nullifies actors deleted after capture", context do
    project = Repo.get!(Project, context.restore.project_id)
    _source_language = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    reviewer = Repo.insert!(%User{email: unique_user_email()})
    flow = flow_fixture(project, %{name: "Historical attribution"})
    dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
    text = Localization.get_text_by_source("flow_node", dialogue.id, "text", "es")

    assert {:ok, _text} =
             Localization.update_text(text, %{
               translated_text: "Hola",
               status: "final",
               translated_by_id: context.restore.requested_by_id,
               reviewed_by_id: reviewer.id
             })

    target_object = active_project_object(project.id)
    [snapshot_text] = target_object["localization"]["texts"]
    assert snapshot_text["translated_by_id"] == context.restore.requested_by_id
    assert snapshot_text["reviewed_by_id"] == reviewer.id

    Repo.delete!(reviewer)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)

    restored_text =
      Repo.one!(
        from(candidate in LocalizedText,
          where:
            candidate.project_id == ^project.id and is_nil(candidate.archived_at) and
              candidate.source_type == "flow_node" and candidate.source_field == "text" and
              candidate.translated_text == "Hola"
        )
      )

    assert restored_text.translated_by_id == context.restore.requested_by_id
    assert restored_text.reviewed_by_id == nil
  end

  test "semantic postverification rejects a same-count sheet field mutation", context do
    %{project: project, sheet: original_sheet} = prepare_semantic_target(context)

    assert {:retry, {:project_snapshot_restore_semantic_mismatch, path}} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery,
               before_postverify: fn ->
                 Repo.update_all(
                   from(sheet in Sheet,
                     where: sheet.project_id == ^project.id and is_nil(sheet.deleted_at)
                   ),
                   set: [name: "same count, wrong sheet"]
                 )

                 Localization.sync_sheet_names(project.id)
               end
             )

    assert List.last(path) in ["name", "source_text"]
    assert is_nil(Repo.get!(Sheet, original_sheet.id).deleted_at)
  end

  test "semantic postverification rejects a same-count localized text mutation", context do
    %{project: project, text: original_text} = prepare_semantic_target(context)

    assert {:retry, {:project_snapshot_restore_semantic_mismatch, path}} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery,
               before_postverify: fn ->
                 Repo.update_all(
                   from(text in LocalizedText,
                     where:
                       text.project_id == ^project.id and is_nil(text.archived_at) and
                         text.source_type == "flow_node" and text.source_field == "text"
                   ),
                   set: [translated_text: "same count, wrong translation"]
                 )

                 :ok
               end
             )

    assert List.last(path) == "translated_text"
    refute Repo.get!(LocalizedText, original_text.id).archived_at
  end

  test "semantic postverification sorts localization after source IDs are remapped", context do
    project = Repo.get!(Project, context.restore.project_id)
    _source_language = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    sheet = sheet_fixture(project, %{name: "Reordered localized blocks"})

    first =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "First localized block", "placeholder" => ""},
        value: %{"content" => "First source"}
      })

    second =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Second localized block", "placeholder" => ""},
        value: %{"content" => "Second source"}
      })

    assert first.id < second.id

    first_source_hash = sha256("First source")
    second_source_hash = sha256("Second source")

    first_text =
      localized_text_fixture(project.id, %{
        source_type: "block",
        source_id: first.id,
        source_text: "First source",
        source_text_hash: first_source_hash,
        locale_code: "es",
        translated_text: "Primero",
        translated_source_hash: first_source_hash
      })

    second_text =
      localized_text_fixture(project.id, %{
        source_type: "block",
        source_id: second.id,
        source_text: "Second source",
        source_text_hash: second_source_hash,
        locale_code: "es",
        translated_text: "Segundo",
        translated_source_hash: second_source_hash
      })

    assert first_text.source_id == first.id
    assert second_text.source_id == second.id
    assert {:ok, [_second, _first]} = Storyarn.Sheets.reorder_blocks(sheet.id, [second.id, first.id])

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)

    assert Enum.sort(
             Repo.all(
               from text in LocalizedText,
                 where:
                   text.project_id == ^project.id and text.source_type == "block" and
                     is_nil(text.archived_at),
                 select: text.translated_text
             )
           ) == ["Primero", "Segundo"]
  end

  test "semantic postverification never treats a business integer as an entity id", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Position collision"})

    Repo.update_all(from(row in Sheet, where: row.id == ^sheet.id), set: [position: sheet.id])
    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:retry, {:project_snapshot_restore_semantic_mismatch, path}} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery,
               before_postverify: fn ->
                 restored =
                   Repo.one!(
                     from(row in Sheet,
                       where: row.project_id == ^project.id and is_nil(row.deleted_at)
                     )
                   )

                 Repo.update_all(from(row in Sheet, where: row.id == ^restored.id), set: [position: restored.id])
                 :ok
               end
             )

    assert List.last(path) == "position"
  end

  test "typed identity maps tolerate equal numeric ids from different entity tables", context do
    project = Repo.get!(Project, context.restore.project_id)
    flow = flow_fixture(project, %{name: "Colliding flow"})

    %Sheet{id: flow.id, project_id: project.id}
    |> Sheet.create_changeset(%{name: "Colliding sheet", shortcut: "colliding-sheet"})
    |> Repo.insert!()

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)
  end

  test "shortcutless variable namespaces are rewritten across formulas, flows, and scenes", context do
    project = Repo.get!(Project, context.restore.project_id)
    target_sheet = sheet_fixture(project, %{name: "Shortcutless variable target"})

    variable =
      block_fixture(target_sheet, %{
        type: "number",
        is_constant: false,
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    Repo.update_all(from(sheet in Sheet, where: sheet.id == ^target_sheet.id), set: [shortcut: nil])
    source_namespace = Integer.to_string(target_sheet.id)

    formula_sheet = sheet_fixture(project, %{name: "Formula namespace owner"})
    formula_table = table_block_fixture(formula_sheet, %{label: "Computed values"})
    formula_column = table_column_fixture(formula_table, %{name: "Projected", type: "formula"})
    formula_row = hd(formula_table.table_rows)

    assert {:ok, _row} =
             Storyarn.Sheets.update_table_cell(formula_row, formula_column.slug, %{
               "expression" => "source",
               "bindings" => %{
                 "source" => %{
                   "type" => "variable",
                   "ref" => "#{source_namespace}.#{variable.variable_name}"
                 }
               }
             })

    flow = flow_fixture(project, %{name: "Shortcutless flow owner"})

    _instruction =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [variable_assignment(source_namespace, variable.variable_name)]
        }
      })

    scene = scene_fixture(project, %{name: "Shortcutless scene owner"})
    pin = pin_fixture(scene, %{"label" => "Variable condition"})

    assert {:ok, _pin} =
             Scenes.update_pin(pin, %{
               "condition" => variable_condition(source_namespace, variable.variable_name)
             })

    zone = zone_fixture(scene, %{"name" => "Variable assignment"})

    assert {:ok, _zone} =
             Scenes.update_zone(zone, %{
               "action_type" => "action",
               "action_data" => %{
                 "assignments" => [variable_assignment(source_namespace, variable.variable_name)]
               }
             })

    target_object = active_project_object(project.id)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)

    restored_target =
      Repo.one!(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project.id and sheet.name == "Shortcutless variable target" and
              is_nil(sheet.deleted_at)
        )
      )

    refute restored_target.id == target_sheet.id
    assert is_nil(restored_target.shortcut)
    destination_namespace = Integer.to_string(restored_target.id)

    restored_variable =
      Repo.one!(
        from(block in Block,
          where:
            block.sheet_id == ^restored_target.id and block.variable_name == ^variable.variable_name and
              is_nil(block.deleted_at)
        )
      )

    restored_formula_sheet =
      Repo.one!(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project.id and sheet.name == "Formula namespace owner" and
              is_nil(sheet.deleted_at)
        )
      )

    restored_formula_table =
      Repo.one!(
        from(block in Block,
          where: block.sheet_id == ^restored_formula_sheet.id and block.type == "table" and is_nil(block.deleted_at)
        )
      )

    [restored_formula_row] = Storyarn.Sheets.list_table_rows(restored_formula_table.id)

    assert get_in(restored_formula_row.cells, [formula_column.slug, "bindings", "source", "ref"]) ==
             "#{destination_namespace}.#{variable.variable_name}"

    restored_instruction =
      Repo.one!(
        from(node in FlowNode,
          join: restored_flow in Flow,
          on: restored_flow.id == node.flow_id,
          where:
            restored_flow.project_id == ^project.id and restored_flow.name == "Shortcutless flow owner" and
              is_nil(restored_flow.deleted_at) and is_nil(node.deleted_at) and node.type == "instruction"
        )
      )

    assert hd(restored_instruction.data["assignments"])["sheet"] == destination_namespace

    restored_scene =
      Repo.one!(
        from(scene in Scene,
          where:
            scene.project_id == ^project.id and scene.name == "Shortcutless scene owner" and
              is_nil(scene.deleted_at)
        )
      )

    [restored_pin] = Scenes.list_pins(restored_scene.id)
    [restored_zone] = Scenes.list_zones(restored_scene.id)

    assert get_in(restored_pin.condition, ["blocks", Access.at(0), "rules", Access.at(0), "sheet"]) ==
             destination_namespace

    assert hd(restored_zone.action_data["assignments"])["sheet"] == destination_namespace

    assert Enum.sort(
             Repo.all(
               from(reference in VariableReference,
                 where: reference.block_id == ^restored_variable.id,
                 select: {reference.source_type, reference.kind}
               )
             )
           ) == [{"flow_node", "write"}, {"scene_pin", "read"}, {"scene_zone", "write"}]
  end

  test "explicit numeric shortcuts remain authoritative over historical id fallbacks", context do
    project = Repo.get!(Project, context.restore.project_id)
    fallback_sheet = sheet_fixture(project, %{name: "Shadowed fallback owner", position: 0})

    _shadowed_variable =
      block_fixture(fallback_sheet, %{
        type: "number",
        is_constant: false,
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    Repo.update_all(from(sheet in Sheet, where: sheet.id == ^fallback_sheet.id), set: [shortcut: nil])
    numeric_namespace = Integer.to_string(fallback_sheet.id)

    explicit_sheet =
      sheet_fixture(project, %{
        name: "Explicit numeric owner",
        position: 1,
        shortcut: numeric_namespace
      })

    explicit_variable =
      block_fixture(explicit_sheet, %{
        type: "number",
        is_constant: false,
        config: %{"label" => "Mana", "placeholder" => "0"}
      })

    flow = flow_fixture(project, %{name: "Explicit numeric namespace flow"})

    _instruction =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            variable_assignment(numeric_namespace, explicit_variable.variable_name)
          ]
        }
      })

    target_object = active_project_object(project.id)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)

    restored_explicit =
      Repo.one!(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project.id and sheet.name == "Explicit numeric owner" and
              is_nil(sheet.deleted_at)
        )
      )

    assert restored_explicit.shortcut == numeric_namespace

    restored_variable =
      Repo.one!(
        from(block in Block,
          where:
            block.sheet_id == ^restored_explicit.id and
              block.variable_name == ^explicit_variable.variable_name and is_nil(block.deleted_at)
        )
      )

    restored_instruction =
      Repo.one!(
        from(node in FlowNode,
          join: restored_flow in Flow,
          on: restored_flow.id == node.flow_id,
          where:
            restored_flow.project_id == ^project.id and
              restored_flow.name == "Explicit numeric namespace flow" and
              is_nil(restored_flow.deleted_at) and is_nil(node.deleted_at) and
              node.type == "instruction"
        )
      )

    assert hd(restored_instruction.data["assignments"])["sheet"] == numeric_namespace

    assert Repo.exists?(
             from(reference in VariableReference,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^restored_instruction.id and
                   reference.block_id == ^restored_variable.id and reference.kind == "write"
             )
           )
  end

  test "a generated shortcutless namespace retries locally past a fixed numeric shortcut", context do
    project = Repo.get!(Project, context.restore.project_id)
    generated_sheet = sheet_fixture(project, %{name: "A generated namespace", position: 0})

    variable =
      block_fixture(generated_sheet, %{
        type: "number",
        is_constant: false,
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    fixed_sheet = sheet_fixture(project, %{name: "B fixed numeric namespace", position: 1})

    _fixed_variable =
      block_fixture(fixed_sheet, %{
        type: "number",
        is_constant: false,
        config: %{"label" => "Mana", "placeholder" => "0"}
      })

    Repo.update_all(from(sheet in Sheet, where: sheet.id == ^generated_sheet.id), set: [shortcut: nil])

    %{rows: [[consumed_id]]} =
      Repo.query!("SELECT nextval(pg_get_serial_sequence('sheets', 'id'))::bigint")

    colliding_destination_id = consumed_id + 1
    fixed_namespace = Integer.to_string(colliding_destination_id)

    Repo.update_all(
      from(sheet in Sheet, where: sheet.id == ^fixed_sheet.id),
      set: [shortcut: fixed_namespace]
    )

    flow = flow_fixture(project, %{name: "Numeric collision flow"})

    _instruction =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            variable_assignment(Integer.to_string(generated_sheet.id), variable.variable_name)
          ]
        }
      })

    target_object = active_project_object(project.id)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)
    Process.delete({CountingEmptyMaterializer, :stage_count})

    reservation_count = Repo.aggregate(StorageReservation, :count, :id)

    assert {:ok, result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: CountingEmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    assert is_binary(result.semantic_digest)
    assert Process.get({CountingEmptyMaterializer, :stage_count}) == 1
    assert Repo.aggregate(StorageReservation, :count, :id) == reservation_count + 1

    restored_generated =
      Repo.one!(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project.id and sheet.name == "A generated namespace" and
              is_nil(sheet.deleted_at)
        )
      )

    restored_fixed =
      Repo.one!(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project.id and sheet.name == "B fixed numeric namespace" and
              is_nil(sheet.deleted_at)
        )
      )

    assert restored_generated.id > colliding_destination_id
    assert is_nil(restored_generated.shortcut)
    assert restored_fixed.shortcut == fixed_namespace

    restored_instruction =
      Repo.one!(
        from(node in FlowNode,
          join: restored_flow in Flow,
          on: restored_flow.id == node.flow_id,
          where:
            restored_flow.project_id == ^project.id and restored_flow.name == "Numeric collision flow" and
              is_nil(restored_flow.deleted_at) and is_nil(node.deleted_at) and node.type == "instruction"
        )
      )

    assert hd(restored_instruction.data["assignments"])["sheet"] ==
             Integer.to_string(restored_generated.id)

    assert Repo.aggregate(
             from(sheet in Sheet, where: sheet.project_id == ^project.id and is_nil(sheet.deleted_at)),
             :count
           ) == 2
  end

  test "mention-looking block config remains literal business text", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Literal config owner"})

    _block =
      block_fixture(sheet, %{
        type: "rich_text",
        config: %{
          "label" => "Probe",
          "placeholder" => ~s(<span class="mention" data-type="sheet" data-id="#{sheet.id}">literal</span>)
        },
        value: %{"content" => "ordinary content"}
      })

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )
  end

  test "exact restore remaps a rich-text mention with uppercase attributes", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Uppercase mention target"})

    _block =
      block_fixture(sheet, %{
        type: "rich_text",
        config: %{"label" => "Biography", "placeholder" => ""},
        value: %{
          "content" => ~s(<span CLASS="mention" DATA-TYPE="sheet" DATA-ID="#{sheet.id}">target</span>)
        }
      })

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_sheet =
      Repo.one!(
        from(row in Sheet,
          where:
            row.project_id == ^project.id and row.name == "Uppercase mention target" and
              is_nil(row.deleted_at)
        )
      )

    restored_block =
      Repo.one!(from(row in Block, where: row.sheet_id == ^restored_sheet.id and is_nil(row.deleted_at)))

    assert {:ok, [%{type: "sheet", id: restored_id}]} =
             RichTextMentions.extract_from_html(restored_block.value["content"])

    assert restored_id == Integer.to_string(restored_sheet.id)
  end

  test "mention-looking markup in a simple text block remains literal", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Literal text mention target"})
    literal = ~s(<span CLASS="mention" DATA-TYPE="sheet" DATA-ID="#{sheet.id}">literal</span>)

    _block =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Literal", "placeholder" => ""},
        value: %{"content" => literal}
      })

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_sheet =
      Repo.one!(
        from(row in Sheet,
          where:
            row.project_id == ^project.id and row.name == "Literal text mention target" and
              is_nil(row.deleted_at)
        )
      )

    restored_block =
      Repo.one!(from(row in Block, where: row.sheet_id == ^restored_sheet.id and is_nil(row.deleted_at)))

    assert restored_block.value["content"] == literal

    refute Repo.exists?(
             from(reference in EntityReference,
               where: reference.source_type == "block" and reference.source_id == ^restored_block.id
             )
           )
  end

  test "uppercase mention-looking class in rich text remains byte-identical", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Uppercase literal owner"})
    literal = ~s(<SPAN CLASS="MENTION" DATA-TYPE="sheet" DATA-ID="#{sheet.id}">&#169;</SPAN>)

    _block =
      block_fixture(sheet, %{
        type: "rich_text",
        config: %{"label" => "Literal", "placeholder" => ""},
        value: %{"content" => literal}
      })

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_sheet =
      Repo.one!(
        from(row in Sheet,
          where:
            row.project_id == ^project.id and row.name == "Uppercase literal owner" and
              is_nil(row.deleted_at)
        )
      )

    restored_block =
      Repo.one!(from(row in Block, where: row.sheet_id == ^restored_sheet.id and is_nil(row.deleted_at)))

    assert restored_block.value["content"] == literal
  end

  test "exact restore remaps a rich-text mention whose class uses an HTML entity", context do
    project = Repo.get!(Project, context.restore.project_id)
    sheet = sheet_fixture(project, %{name: "Entity mention target"})
    flow = flow_fixture(project, %{name: "Entity mention owner"})

    _dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => ~s(<span class="m&#101;ntion" data-type="sheet" data-id="#{sheet.id}">target</span>),
          "responses" => []
        }
      })

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_sheet =
      Repo.one!(
        from(row in Sheet,
          where:
            row.project_id == ^project.id and row.name == "Entity mention target" and
              is_nil(row.deleted_at)
        )
      )

    restored_node =
      Repo.one!(
        from(node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where:
            flow.project_id == ^project.id and flow.name == "Entity mention owner" and
              is_nil(flow.deleted_at) and is_nil(node.deleted_at) and node.type == "dialogue"
        )
      )

    assert {:ok, [%{type: "sheet", id: restored_id}]} =
             RichTextMentions.extract_from_html(restored_node.data["text"])

    assert restored_id == Integer.to_string(restored_sheet.id)
  end

  test "a dialogue response key that looks like a dynamic exit remains literal", context do
    project = Repo.get!(Project, context.restore.project_id)
    flow = flow_fixture(project, %{name: "Literal exit response"})
    source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Choose", "responses" => []}})
    target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Continue", "responses" => []}})
    response_key = "exit_#{source.id}"

    assert {:ok, source, _effects} =
             Storyarn.Flows.update_node_data(source, %{
               "text" => "Choose",
               "responses" => [%{"id" => response_key, "text" => "Continue"}]
             })

    _connection =
      Storyarn.FlowsFixtures.connection_fixture(flow, source, target, %{source_pin: response_key})

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored_connection =
      Repo.one!(
        from(connection in FlowConnection,
          join: restored_flow in Flow,
          on: restored_flow.id == connection.flow_id,
          where:
            restored_flow.project_id == ^project.id and restored_flow.name == "Literal exit response" and
              is_nil(restored_flow.deleted_at)
        )
      )

    assert restored_connection.source_pin == response_key
    refute restored_connection.source_node_id == source.id
  end

  test "exact restore preserves a stale non-current translated source hash", context do
    %{project: project, text: text} = prepare_semantic_target(context)
    stale_hash = String.duplicate("a", 64)

    Repo.update_all(
      from(row in LocalizedText, where: row.id == ^text.id),
      set: [translated_source_hash: stale_hash, status: "review"]
    )

    target_object = active_project_object(project.id)
    Process.put({EmptyArchiveReader, :project_object}, target_object)

    assert {:ok, _result} =
             ProjectSnapshotRestoreExecutor.execute(context.restore,
               archive_reader: EmptyArchiveReader,
               asset_materializer: EmptyMaterializer,
               project_recovery: ProjectRecovery
             )

    restored =
      Repo.one!(
        from(row in LocalizedText,
          where:
            row.project_id == ^project.id and is_nil(row.archived_at) and
              row.source_type == "flow_node" and row.source_field == "text"
        )
      )

    assert restored.translated_text == "Hola exacta"
    assert restored.translated_source_hash == stale_hash
    assert restored.status == "review"
  end

  test "restores the exact canonical asset catalog after captured rows and objects disappear" do
    user = user_fixture()
    project = project_fixture(user)
    scope = user_scope_fixture(user)
    shared_bytes = "one immutable image payload shared by two logical assets"
    variant_bytes = "an independently stored thumbnail variant"
    orphan_bytes = "an unreferenced logical asset that still belongs to the catalog"

    assert {:ok, original} =
             Assets.upload_binary_and_create_asset(
               shared_bytes,
               %{filename: "duplicate.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, web} =
             Assets.upload_binary_and_create_asset(
               shared_bytes,
               %{filename: "duplicate.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, variant} =
             Assets.upload_binary_and_create_asset(
               variant_bytes,
               %{filename: "variant.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, orphan} =
             Assets.upload_binary_and_create_asset(
               orphan_bytes,
               %{filename: "orphan.png", content_type: "image/png"},
               project,
               user
             )

    assert original.blob_hash == web.blob_hash

    assert {:ok, original} =
             Assets.update_asset(original, %{
               metadata: %{
                 "restore_role" => "original",
                 "web_asset_id" => web.id,
                 "variant_asset_ids" => %{"thumbnail" => variant.id},
                 "width" => 800,
                 "height" => 600
               }
             })

    assert {:ok, web} =
             Assets.update_asset(web, %{
               metadata: %{
                 "restore_role" => "web",
                 "original_asset_id" => original.id,
                 "width" => 400,
                 "height" => 300
               }
             })

    assert {:ok, variant} =
             Assets.update_asset(variant, %{
               metadata: %{"restore_role" => "variant", "original_asset_id" => original.id}
             })

    assert {:ok, orphan} =
             Assets.update_asset(orphan, %{
               metadata: %{"restore_role" => "orphan", "purpose" => "portable-catalog-sentinel"}
             })

    sheet = sheet_fixture(project, %{name: "Archive asset owner"})

    assert {:ok, _sheet} =
             Storyarn.Sheets.update_sheet(sheet, %{
               banner_asset_id: original.id
             })

    pretrash = image_asset_fixture(project, user, %{filename: "historical-trash.png"})
    assert {:ok, _pretrash} = Assets.move_asset_to_trash(project.id, pretrash.id, user.id)
    pretrash_before = Repo.get!(Asset, pretrash.id)

    active_assets = Assets.list_assets_for_export(project.id)

    {captured_hashes, captured_metadata} =
      AssetHashResolver.capture_catalog_maps(active_assets)

    authored_original_metadata = %{
      "restore_role" => "original",
      "original_asset_id" => [original.id],
      "web_asset_id" => web.id,
      "variant_asset_ids" => %{
        "thumbnail" => variant.id,
        "dangling" => 999_999_999,
        "malformed" => [variant.id]
      },
      "width" => 800,
      "height" => 600
    }

    capture =
      project.id
      |> capture_project_object()
      |> Map.put(
        "asset_restore_contract_version",
        AssetHashResolver.exact_restore_contract_version()
      )
      |> Map.put(
        "asset_blob_hashes",
        Map.put(captured_hashes, to_string(original.id), String.duplicate("0", 64))
      )
      |> Map.put(
        "asset_metadata",
        Map.update!(captured_metadata, to_string(original.id), fn metadata ->
          metadata
          |> Map.put("filename", "../authored-duplicate.png")
          |> Map.put("content_type", "text/html")
          |> Map.put("size", 999_999_999)
          |> Map.put("persisted_metadata", authored_original_metadata)
        end)
      )

    captured_assets = [original, web, variant, orphan]
    captured_ids = Enum.map(captured_assets, & &1.id)
    captured_logical_keys = Enum.map(captured_assets, & &1.key)

    assert Enum.sort(Enum.map(active_assets, & &1.id)) == Enum.sort(captured_ids)

    assert {:ok, prepared} =
             SnapshotArchiveStorage.prepare(project.id, capture, active_assets, source_key_mode: :protected_blob)

    assert {:ok, zip_plan} = ProjectSnapshotZip.prepare_capture(project.id, prepared)
    archive = zip_plan |> ProjectSnapshotZip.stream() |> Enum.to_list() |> IO.iodata_to_binary()
    token = archive_token()
    prefix = SnapshotArchiveStorage.ready_prefix(project.id, token)
    archive_key = SnapshotArchiveStorage.archive_key(prefix)
    manifest_key = SnapshotArchiveStorage.manifest_key(prefix)

    assert {:ok, _url} = Storage.upload(archive_key, archive, "application/zip")
    assert {:ok, _url} = Storage.upload(manifest_key, prepared.manifest_json, "application/json")
    on_exit(fn -> delete_project_storage(project.id) end)

    snapshot =
      full_project_snapshot_fixture(project, %{
        object_prefix: prefix,
        archive_storage_key: archive_key,
        archive_size_bytes: byte_size(archive),
        archive_checksum: sha256(archive),
        project_size_bytes: prepared.project_size_bytes,
        project_checksum: prepared.project_checksum,
        manifest_storage_key: manifest_key,
        manifest_size_bytes: prepared.manifest_size_bytes,
        manifest_checksum: prepared.manifest_checksum,
        total_size_bytes: byte_size(archive) + prepared.manifest_size_bytes,
        accounted_size_bytes: byte_size(archive) + prepared.manifest_size_bytes,
        asset_blob_size_bytes: prepared.asset_blob_size_bytes,
        asset_count: 4,
        blob_count: 3,
        capture_digest: prepared.capture_digest,
        entity_counts: capture["entity_counts"]
      })

    restore = request_and_claim_restore(scope, project, snapshot)

    assert {:ok, _sheet} =
             Storyarn.Sheets.update_sheet(Repo.get!(Sheet, sheet.id), %{
               banner_asset_id: nil
             })

    {4, nil} = Repo.delete_all(from(asset in Asset, where: asset.id in ^captured_ids))
    assert Enum.all?(captured_ids, &is_nil(Repo.get(Asset, &1)))
    Enum.each(captured_logical_keys, fn key -> assert :ok = Local.delete(key) end)

    captured_blob_keys =
      captured_assets
      |> Enum.map(&BlobStore.blob_key(project.id, &1.blob_hash, "png"))
      |> Enum.uniq()

    assert length(captured_blob_keys) == 3
    Enum.each(captured_blob_keys, fn key -> assert :ok = Local.delete(key) end)

    assert {:ok, current_only} =
             Assets.upload_binary_and_create_asset(
               "current-only bytes that must move to recovery trash",
               %{filename: "current-only.png", content_type: "image/png"},
               project,
               user
             )

    assert {:ok, result} = ProjectSnapshotRestoreExecutor.execute(restore, [])

    completed = Repo.get!(ProjectSnapshotRestore, restore.id)
    reservation = Repo.get!(StorageReservation, result.reservation_id)
    assert completed.status == "completed"
    assert completed.result_digest == result.result_digest
    assert reservation.status == "committed"
    assert length(reservation.cleanup_storage_keys) == 10
    assert is_integer(result.cleanup_request_id)

    active_assets =
      Repo.all(
        from asset in Asset,
          where: asset.project_id == ^project.id and is_nil(asset.deleted_at),
          order_by: [asc: asset.id]
      )

    assert length(active_assets) == 4
    assert Enum.count(active_assets, &(&1.filename == "duplicate.png")) == 1

    assert Enum.sort(Enum.map(active_assets, & &1.filename)) ==
             ["../authored-duplicate.png", "duplicate.png", "orphan.png", "variant.png"]

    assert Enum.all?(active_assets, &(&1.id not in captured_ids))
    assert length(Enum.uniq(Enum.map(active_assets, & &1.id))) == 4
    assert length(Enum.uniq(Enum.map(active_assets, & &1.blob_hash))) == 3

    restored_by_role = Map.new(active_assets, &{&1.metadata["restore_role"], &1})
    assert restored_by_role |> Map.keys() |> Enum.sort() == ["original", "orphan", "variant", "web"]
    restored_original = restored_by_role["original"]
    restored_web = restored_by_role["web"]
    restored_variant = restored_by_role["variant"]
    restored_orphan = restored_by_role["orphan"]
    assert restored_original.content_type == "image/png"
    assert restored_original.size == byte_size(shared_bytes)
    assert restored_original.blob_hash == original.blob_hash
    assert restored_original.metadata["original_asset_id"] == [original.id]
    assert restored_original.metadata["web_asset_id"] == restored_web.id

    assert restored_original.metadata["variant_asset_ids"] == %{
             "thumbnail" => restored_variant.id,
             "dangling" => 999_999_999,
             "malformed" => [variant.id]
           }

    assert restored_web.metadata["original_asset_id"] == restored_original.id
    assert restored_variant.metadata["original_asset_id"] == restored_original.id
    assert restored_orphan.metadata["purpose"] == "portable-catalog-sentinel"

    expected_asset_bytes =
      2 * byte_size(shared_bytes) + byte_size(variant_bytes) + byte_size(orphan_bytes)

    assert Storyarn.Platform.Billing.project_storage_usage(project.id).current_assets == %{
             bytes: expected_asset_bytes,
             count: 4
           }

    restored_sheet =
      Repo.one!(
        from candidate in Sheet,
          where:
            candidate.project_id == ^project.id and candidate.name == "Archive asset owner" and
              is_nil(candidate.deleted_at)
      )

    assert restored_sheet.banner_asset_id == restored_original.id
    assert {:ok, ^shared_bytes} = Storage.download(restored_original.key)
    assert {:ok, ^shared_bytes} = Storage.download(restored_web.key)
    assert {:ok, ^variant_bytes} = Storage.download(restored_variant.key)
    assert {:ok, ^orphan_bytes} = Storage.download(restored_orphan.key)

    assert {:ok, ^shared_bytes} =
             Storage.download(BlobStore.blob_key(project.id, restored_original.blob_hash, "png"))

    assert {:ok, ^variant_bytes} =
             Storage.download(BlobStore.blob_key(project.id, restored_variant.blob_hash, "png"))

    assert {:ok, ^orphan_bytes} =
             Storage.download(BlobStore.blob_key(project.id, restored_orphan.blob_hash, "png"))

    assert Repo.get!(Asset, current_only.id).deleted_at
    assert Repo.get!(Asset, pretrash.id) == pretrash_before
  end

  defp run_to_injected_failure(restore, snapshot) do
    ProjectSnapshotRestoreExecutor.execute(restore,
      archive_reader: reader(snapshot),
      asset_materializer: FailingMaterializer,
      project_recovery: AcceptingRecovery
    )
  end

  defp prepare_semantic_target(context) do
    project = Repo.get!(Project, context.restore.project_id)
    _source_language = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target_language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    sheet = sheet_fixture(project, %{name: "Semantic character"})
    flow = flow_fixture(project, %{name: "Semantic dialogue"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Exact hello", "speaker_sheet_id" => sheet.id, "responses" => []}
      })

    text = Localization.get_text_by_source("flow_node", dialogue.id, "text", "es")

    assert {:ok, text} =
             Localization.update_text(text, %{
               translated_text: "Hola exacta",
               status: "final",
               translator_notes: "semantic receipt"
             })

    target_object = active_project_object(project.id)
    assert :ok = ProjectRecovery.validate_materialization_snapshot(target_object)
    Process.put({EmptyArchiveReader, :project_object}, target_object)
    %{project: project, sheet: sheet, flow: flow, dialogue: dialogue, text: text, target: target_object}
  end

  defp reader(snapshot) do
    _snapshot = snapshot
    EmptyArchiveReader
  end

  defp empty_project_object(project) do
    %{
      "format_version" => 2,
      "project" => %{
        "name" => project.name,
        "description" => project.description,
        "project_type" => project.project_type,
        "project_subtype" => project.project_subtype,
        "project_type_other" => project.project_type_other,
        "settings" => project.settings,
        "auto_version_flows" => project.auto_version_flows,
        "auto_version_scenes" => project.auto_version_scenes,
        "auto_version_sheets" => project.auto_version_sheets
      },
      "entity_counts" => %{
        "sheets" => 0,
        "flows" => 0,
        "scenes" => 0,
        "languages" => 0,
        "localized_texts" => 0,
        "glossary_entries" => 0
      },
      "asset_blob_hashes" => %{},
      "asset_metadata" => %{},
      "asset_catalog_refs" => %{},
      "sheets" => [],
      "flows" => [],
      "scenes" => [],
      "tree" => %{"sheets" => [], "flows" => [], "scenes" => []},
      "localization" => %{"languages" => [], "texts" => [], "glossary" => []}
    }
  end

  defp active_project_object(project_id) do
    {:ok, snapshot} =
      Repo.repeatable_read(fn ->
        ProjectSnapshotBuilder.build_snapshot_in_transaction(project_id,
          localization_scope: :active
        )
      end)

    normalized = snapshot |> Jason.encode!() |> Jason.decode!()
    {:ok, portable} = SnapshotObjectFormat.portable_project(normalized)

    Map.put(portable, "asset_catalog_refs", %{})
  end

  defp capture_project_object(project_id) do
    {:ok, snapshot} =
      Repo.repeatable_read(fn ->
        ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(project_id,
          localization_scope: :active
        )
      end)

    snapshot |> Jason.encode!() |> Jason.decode!()
  end

  defp variable_condition(sheet_namespace, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_namespace,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end

  defp variable_assignment(sheet_namespace, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_namespace,
      "variable" => variable_name,
      "operator" => "set",
      "value_type" => "literal",
      "value" => "1"
    }
  end

  defp request_and_claim_restore(scope, project, snapshot) do
    assert {:ok, requested} =
             Versioning.request_project_snapshot_restore(scope, project, snapshot, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.oban_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, {:claimed, restore}} =
             Versioning.claim_project_snapshot_restore(requested.id, 1,
               job_id: job.id,
               attempt: 1
             )

    restore
  end

  defp archive_token do
    Ecto.UUID.generate() |> String.replace("-", "") |> binary_part(0, 16)
  end

  defp delete_project_storage(project_id) do
    prefix = "projects/#{project_id}/"
    {:ok, %{objects: objects, cursor: nil}} = Local.list_prefix(prefix, limit: 10_000)
    Enum.each(objects, &Local.delete(&1.key))
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
