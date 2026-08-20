defmodule Storyarn.Versioning.WorkspaceSnapshotImportsIntegrationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Billing
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Notifications.Notification
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Versioning.WorkspaceSnapshotImports
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.ImportProjectSnapshotWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @concurrency_timeout 10_000
  @concurrency_poll_interval 20

  defmodule RetryableAssetStagingFailure do
    @moduledoc false

    defdelegate prepare(project_id, owner_token, manifest, project, staging_prefix, staging_keys),
      to: ProjectSnapshotAssetMaterializer

    defdelegate planned_storage_keys(asset_plan),
      to: ProjectSnapshotAssetMaterializer

    def stage_destination_objects(_asset_plan, _tracker) do
      {:error, {:snapshot_asset_staging_failed, "logical", {:destination_stat_failed, {:http_error, 503, %{}}}}}
    end
  end

  defmodule ClientAssetStagingFailure do
    @moduledoc false

    defdelegate prepare(project_id, owner_token, manifest, project, staging_prefix, staging_keys),
      to: ProjectSnapshotAssetMaterializer

    defdelegate planned_storage_keys(asset_plan),
      to: ProjectSnapshotAssetMaterializer

    def stage_destination_objects(_asset_plan, _tracker) do
      {:error, {:snapshot_asset_staging_failed, "logical", {:destination_stat_failed, {:http_error, 400, %{}}}}}
    end
  end

  defmodule IntegrityAssetStagingFailure do
    @moduledoc false

    defdelegate prepare(project_id, owner_token, manifest, project, staging_prefix, staging_keys),
      to: ProjectSnapshotAssetMaterializer

    defdelegate planned_storage_keys(asset_plan),
      to: ProjectSnapshotAssetMaterializer

    def stage_destination_objects(_asset_plan, _tracker) do
      {:error,
       {:snapshot_asset_staging_failed, "logical",
        {:snapshot_object_checksum_mismatch, String.duplicate("a", 64), String.duplicate("b", 64)}}}
    end
  end

  defmodule RaisedTransientAssetStagingFailure do
    @moduledoc false

    defdelegate prepare(project_id, owner_token, manifest, project, staging_prefix, staging_keys),
      to: ProjectSnapshotAssetMaterializer

    defdelegate planned_storage_keys(asset_plan),
      to: ProjectSnapshotAssetMaterializer

    def stage_destination_objects(_asset_plan, _tracker) do
      raise %Req.TransportError{reason: :timeout}
    end
  end

  defmodule RaisedPermanentAssetStagingFailure do
    @moduledoc false

    defdelegate prepare(project_id, owner_token, manifest, project, staging_prefix, staging_keys),
      to: ProjectSnapshotAssetMaterializer

    defdelegate planned_storage_keys(asset_plan),
      to: ProjectSnapshotAssetMaterializer

    def stage_destination_objects(_asset_plan, _tracker) do
      raise ArgumentError, "permanent staging bug"
    end
  end

  defmodule FailingAdmissionStorage do
    @moduledoc false

    def upload_stream(_storage_key, _chunks, _content_type) do
      {:error, {:http_error, 503, %{}}}
    end
  end

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)

    project =
      project_fixture(user, %{
        workspace: workspace,
        name: "Snapshot import source",
        description: "Exact project description",
        settings: %{
          "theme" => %{"primary" => "#123456", "accent" => "#abcdef"},
          "nested" => %{"enabled" => true}
        }
      })

    {:ok, project} =
      Projects.update_project(project, %{
        auto_version_flows: false,
        auto_version_scenes: true,
        auto_version_sheets: false
      })

    %{user: user, scope: user_scope_fixture(user), workspace: workspace, project: project}
  end

  test "quota rejection is synchronous and creates no operation, job, reservation or notification", context do
    _asset = upload_asset!(context.project, context.user, "quota-source.png", "quota source bytes", "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    usage = Billing.workspace_storage_usage(context.workspace.id)
    limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)
    fill_storage_fixture(context.project, context.user, limit - usage.accounted_bytes)

    import_count = Repo.aggregate(WorkspaceSnapshotImport, :count)
    job_count = import_job_count()
    notification_count = import_notification_count(context.user.id)

    assert {:error, :limit_reached, details} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "too-large.zip"}
             )

    assert details.required_bytes > 0
    assert details.available_bytes == 0
    assert details.limit_bytes == limit
    assert Repo.aggregate(WorkspaceSnapshotImport, :count) == import_count
    assert import_job_count() == job_count
    assert import_notification_count(context.user.id) == notification_count

    assert Billing.workspace_storage_usage(context.workspace.id).active_reservations.by_kind[
             "workspace_snapshot_import"
           ] in [nil, 0]

    assert {:ok, %{objects: []}} = Storage.list_prefix(import_prefix(context.workspace.id))
  end

  test "a normal archive upload failure terminalizes synchronous admission and releases capacity", context do
    asset_bytes = "admission failure asset"
    _asset = upload_asset!(context.project, context.user, "admission.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:error, :snapshot_archive_stage_failed} =
             WorkspaceSnapshotImports.request(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "provider-upload-failure.zip"},
               storage: FailingAdmissionStorage
             )

    assert [failed] = Repo.all(WorkspaceSnapshotImport)
    assert failed.status == "failed"
    assert failed.stage == "failed"
    assert failed.reserved_bytes == 0
    assert failed.failure_code == "snapshot_import_failed"
    refute failed.project_id

    assert Repo.aggregate(
             from(import in WorkspaceSnapshotImport,
               where: import.status in ["queued", "running", "retrying"]
             ),
             :count
           ) == 0

    expected_cleanup_keys = Enum.sort(failed.staging_storage_keys)

    assert [%StorageCleanupRequest{storage_keys: ^expected_cleanup_keys}] =
             import_cleanup_requests(failed)

    assert [%Notification{status: "failure"}] = import_notifications(failed)
    assert Billing.workspace_storage_usage(context.workspace.id).active_reservations.by_kind == %{}
  end

  test "accepted request is durable and active request plus duplicate job delivery are idempotent", context do
    asset_bytes = "durable snapshot asset"
    _asset = upload_asset!(context.project, context.user, "durable.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, first} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "durable.zip"}
             )

    assert {:ok, duplicate} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "renamed-but-identical.zip"}
             )

    assert duplicate.id == first.id
    assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 1
    assert import_job_count() == 1
    assert first.status == "queued"
    assert first.stage == "queued"
    assert first.reserved_bytes == byte_size(asset_bytes)
    assert first.oban_job_id
    assert {:ok, %{size: staged_size}} = Storage.stat(first.archive_storage_key)
    assert staged_size == first.archive_size_bytes

    usage = Billing.workspace_storage_usage(context.workspace.id)
    assert usage.active_reservations.by_kind["workspace_snapshot_import"] == byte_size(asset_bytes)

    job = import_job!(first)
    assert :ok = ImportProjectSnapshotWorker.perform(job)
    assert :ok = ImportProjectSnapshotWorker.perform(job)

    completed = Repo.get!(WorkspaceSnapshotImport, first.id)
    assert completed.status == "completed"
    assert completed.stage == "completed"
    assert completed.reserved_bytes == 0
    assert completed.progress_bytes == completed.progress_total_bytes
    assert completed.project_id

    assert Repo.aggregate(
             from(project in Project,
               where: project.workspace_id == ^context.workspace.id and project.id != ^context.project.id
             ),
             :count
           ) == 1

    assert import_notification_count(context.user.id) == 1
  end

  test "a delivery snoozes without claiming the import while its request session lock is held", context do
    asset_bytes = "locked delivery asset"
    _asset = upload_asset!(context.project, context.user, "delivery-lock.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "delivery-lock.zip"}
             )

    before_delivery = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    job = import_job!(accepted)
    parent = self()
    import_id = accepted.id
    lock_name = "workspace-snapshot-import:#{accepted.idempotency_key}"

    lock_owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:workspace_import_delivery_lock_held, import_id})

            receive do
              :release_workspace_import_delivery_lock -> :ok
            end
          end)
        end)
      end)

    assert_receive {:workspace_import_delivery_lock_held, ^import_id}

    delivery_result =
      try do
        Versioning.perform_workspace_snapshot_import(
          accepted.id,
          job_id: job.id,
          attempt: 1,
          max_attempts: ImportProjectSnapshotWorker.max_attempts(),
          lock_acquisition_timeout: 0
        )
      after
        send(lock_owner.pid, :release_workspace_import_delivery_lock)
      end

    assert :ok = Task.await(lock_owner)
    assert delivery_result == {:snooze, 30}

    after_delivery = Repo.get!(WorkspaceSnapshotImport, accepted.id)

    assert Map.take(after_delivery, [
             :status,
             :stage,
             :attempt,
             :reserved_bytes,
             :reserved_project_id,
             :materialization_storage_keys,
             :failure_code,
             :failure_details,
             :started_at,
             :completed_at,
             :updated_at
           ]) ==
             Map.take(before_delivery, [
               :status,
               :stage,
               :attempt,
               :reserved_bytes,
               :reserved_project_id,
               :materialization_storage_keys,
               :failure_code,
               :failure_details,
               :started_at,
               :completed_at,
               :updated_at
             ])

    assert after_delivery.reserved_bytes == byte_size(asset_bytes)
    assert import_cleanup_requests(after_delivery) == []
    assert import_notifications(after_delivery) == []
  end

  test "a transient commit failure preserves its durable plan and succeeds on retry", context do
    asset_bytes = "retryable asset bytes"
    _asset = upload_asset!(context.project, context.user, "retry.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "retry.zip"}
             )

    job = import_job!(accepted)

    transient_commit = fn _workspace_id, _snapshot, _user_id, _opts ->
      {:error, %DBConnection.ConnectionError{message: "transient"}}
    end

    assert {:retry, _reason} =
             Versioning.perform_workspace_snapshot_import(
               accepted.id,
               job_id: job.id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               materialize_fun: transient_commit
             )

    retrying = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert retrying.status == "retrying"
    assert retrying.stage == "retrying"
    assert retrying.reserved_bytes == byte_size(asset_bytes)
    assert retrying.reserved_project_id
    assert retrying.materialization_storage_keys != []
    refute Repo.get(Project, retrying.reserved_project_id)
    assert import_notification_count(context.user.id) == 0

    assert {:ok, stale_cleanup} =
             StorageCompensation.persist_cleanup_request(retrying.materialization_storage_keys)

    test_process = self()

    guarded_commit = fn workspace_id, snapshot, user_id, opts ->
      cleanup_result =
        StorageCompensation.delete_cleanup_request_keys(
          stale_cleanup.id,
          retrying.materialization_storage_keys
        )

      send(test_process, {:stale_cleanup_attempt, cleanup_result})
      ProjectRecovery.materialize_snapshot_import(workspace_id, snapshot, user_id, opts)
    end

    assert {:ok, completed} =
             Versioning.perform_workspace_snapshot_import(
               accepted.id,
               job_id: job.id,
               attempt: 2,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               materialize_fun: guarded_commit
             )

    assert_received {:stale_cleanup_attempt, {:error, skipped_keys}}
    assert Enum.sort(skipped_keys) == Enum.sort(retrying.materialization_storage_keys)
    assert Repo.get!(StorageCleanupRequest, stale_cleanup.id)

    assert completed.status == "completed"
    assert completed.project_id == retrying.reserved_project_id
    assert completed.reserved_project_id == retrying.reserved_project_id
    assert completed.materialization_storage_keys == retrying.materialization_storage_keys
    assert completed.reserved_bytes == 0
    assert import_notification_count(context.user.id) == 1

    Enum.each(completed.materialization_storage_keys, fn storage_key ->
      assert {:ok, %{size: size}} = Storage.stat(storage_key)
      assert size > 0
    end)
  end

  test "reconciliation terminalizes an active import whose final delivery was discarded exactly once", context do
    asset_bytes = "abandoned delivery asset"
    _asset = upload_asset!(context.project, context.user, "abandoned.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "abandoned.zip"}
             )

    job = import_job!(accepted)

    transient_commit = fn _workspace_id, _snapshot, _user_id, _opts ->
      {:error, %DBConnection.ConnectionError{message: "transient before abandoned delivery"}}
    end

    assert {:retry, _reason} =
             Versioning.perform_workspace_snapshot_import(
               accepted.id,
               job_id: job.id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               materialize_fun: transient_commit
             )

    retrying = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert retrying.status == "retrying"
    assert retrying.reserved_bytes == byte_size(asset_bytes)
    assert retrying.materialization_storage_keys != []
    mark_import_job_discarded!(accepted)

    assert %{
             candidate_count: 1,
             terminalized_count: 1,
             changed_count: 0,
             failure_count: 0
           } = Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(limit: 50)

    failed = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert failed.status == "failed"
    assert failed.stage == "failed"
    assert failed.failure_code == "snapshot_import_delivery_abandoned"
    assert failed.reserved_bytes == 0
    assert failed.reserved_project_id == retrying.reserved_project_id
    assert failed.materialization_storage_keys == retrying.materialization_storage_keys

    expected_cleanup_keys =
      (failed.staging_storage_keys ++ failed.materialization_storage_keys)
      |> Enum.uniq()
      |> Enum.sort()

    assert [%StorageCleanupRequest{storage_keys: ^expected_cleanup_keys} = cleanup_request] =
             import_cleanup_requests(failed)

    assert [%Notification{status: "failure"}] = import_notifications(failed)

    assert %{
             candidate_count: 0,
             terminalized_count: 0,
             changed_count: 0,
             failure_count: 0
           } = Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(limit: 50)

    assert [%StorageCleanupRequest{id: cleanup_request_id}] = import_cleanup_requests(failed)
    assert cleanup_request_id == cleanup_request.id
    assert [%Notification{status: "failure"}] = import_notifications(failed)
  end

  test "reconciliation leaves an abandoned import untouched while its request session lock is held", context do
    asset_bytes = "locked abandoned delivery asset"
    _asset = upload_asset!(context.project, context.user, "locked.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "locked-abandoned.zip"}
             )

    mark_import_job_discarded!(accepted)
    before_reconciliation = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    parent = self()
    import_id = accepted.id
    lock_name = "workspace-snapshot-import:#{accepted.idempotency_key}"

    lock_owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:workspace_import_lock_held, import_id})

            receive do
              :release_workspace_import_lock -> :ok
            end
          end)
        end)
      end)

    assert_receive {:workspace_import_lock_held, ^import_id}

    reconciliation =
      try do
        Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(limit: 50)
      after
        send(lock_owner.pid, :release_workspace_import_lock)
      end

    assert :ok = Task.await(lock_owner)

    assert %{
             candidate_count: 1,
             terminalized_count: 0,
             changed_count: 0,
             failure_count: 1
           } = reconciliation

    after_reconciliation = Repo.get!(WorkspaceSnapshotImport, accepted.id)

    assert Map.take(after_reconciliation, [
             :status,
             :stage,
             :reserved_bytes,
             :reserved_project_id,
             :materialization_storage_keys,
             :failure_code,
             :failure_details,
             :completed_at,
             :updated_at
           ]) ==
             Map.take(before_reconciliation, [
               :status,
               :stage,
               :reserved_bytes,
               :reserved_project_id,
               :materialization_storage_keys,
               :failure_code,
               :failure_details,
               :completed_at,
               :updated_at
             ])

    assert after_reconciliation.reserved_bytes == byte_size(asset_bytes)
    assert import_cleanup_requests(after_reconciliation) == []
    assert import_notifications(after_reconciliation) == []
  end

  test "nested provider failures retry only transient staging errors", context do
    asset_bytes = "provider classifier asset"
    _asset = upload_asset!(context.project, context.user, "provider.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, retryable} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "provider-503.zip"}
             )

    retryable_job = import_job!(retryable)

    assert {:retry, _reason} =
             Versioning.perform_workspace_snapshot_import(
               retryable.id,
               job_id: retryable_job.id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               asset_materializer: RetryableAssetStagingFailure
             )

    retrying = Repo.get!(WorkspaceSnapshotImport, retryable.id)
    assert retrying.status == "retrying"
    assert retrying.stage == "retrying"
    assert retrying.reserved_bytes == byte_size(asset_bytes)
    assert import_notifications(retrying) == []

    assert {:ok, completed} =
             Versioning.perform_workspace_snapshot_import(
               retryable.id,
               job_id: retryable_job.id,
               attempt: 2,
               max_attempts: ImportProjectSnapshotWorker.max_attempts()
             )

    assert completed.status == "completed"

    assert {:ok, client_error} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "provider-400.zip"}
             )

    assert {:ok, failed_client_error} =
             Versioning.perform_workspace_snapshot_import(
               client_error.id,
               job_id: import_job!(client_error).id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               asset_materializer: ClientAssetStagingFailure
             )

    assert failed_client_error.status == "failed"
    assert failed_client_error.stage == "failed"
    assert failed_client_error.attempt == 1
    assert failed_client_error.reserved_bytes == 0
    assert [%Notification{status: "failure"}] = import_notifications(failed_client_error)

    assert {:ok, integrity_error} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "provider-integrity.zip"}
             )

    assert {:ok, failed_integrity_error} =
             Versioning.perform_workspace_snapshot_import(
               integrity_error.id,
               job_id: import_job!(integrity_error).id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               asset_materializer: IntegrityAssetStagingFailure
             )

    assert failed_integrity_error.status == "failed"
    assert failed_integrity_error.stage == "failed"
    assert failed_integrity_error.attempt == 1
    assert failed_integrity_error.reserved_bytes == 0
    assert [%Notification{status: "failure"}] = import_notifications(failed_integrity_error)
  end

  test "only explicit transport exceptions raised during asset staging are retryable", context do
    asset_bytes = "raised provider failure asset"
    _asset = upload_asset!(context.project, context.user, "raised.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, transient} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "raised-transport.zip"}
             )

    transient_job = import_job!(transient)

    assert {:retry, _reason} =
             Versioning.perform_workspace_snapshot_import(
               transient.id,
               job_id: transient_job.id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               asset_materializer: RaisedTransientAssetStagingFailure
             )

    retrying = Repo.get!(WorkspaceSnapshotImport, transient.id)
    assert retrying.status == "retrying"
    assert retrying.reserved_bytes == byte_size(asset_bytes)
    assert import_notifications(retrying) == []

    assert {:ok, completed} =
             Versioning.perform_workspace_snapshot_import(
               transient.id,
               job_id: transient_job.id,
               attempt: 2,
               max_attempts: ImportProjectSnapshotWorker.max_attempts()
             )

    assert completed.status == "completed"

    assert {:ok, permanent} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "raised-programming-error.zip"}
             )

    assert {:ok, failed} =
             Versioning.perform_workspace_snapshot_import(
               permanent.id,
               job_id: import_job!(permanent).id,
               attempt: 1,
               max_attempts: ImportProjectSnapshotWorker.max_attempts(),
               asset_materializer: RaisedPermanentAssetStagingFailure
             )

    assert failed.status == "failed"
    assert failed.stage == "failed"
    assert failed.failure_code == "exception"
    assert failed.attempt == 1
    assert failed.reserved_bytes == 0
    assert [%Notification{status: "failure"}] = import_notifications(failed)
  end

  test "a corrupt staged ZIP is terminal on attempt one and emits one failure notification", context do
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "corrupt-after-admission.zip"}
             )

    assert {:ok, staged_archive} = Storage.download(accepted.archive_storage_key)

    assert {:ok, _url} =
             Storage.upload(
               accepted.archive_storage_key,
               corrupt_first_byte(staged_archive),
               "application/zip"
             )

    assert :ok = accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()

    failed = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert failed.status == "failed"
    assert failed.stage == "failed"
    assert failed.attempt == 1
    assert failed.failure_code == "snapshot_zip_local_header_mismatch"
    assert failed.reserved_bytes == 0
    refute failed.project_id
    assert import_notification_count(context.user.id) == 1

    assert [%Notification{status: "failure", dedupe_key: dedupe_key}] =
             Repo.all(
               from(notification in Notification,
                 where:
                   notification.recipient_id == ^context.user.id and
                     notification.entity_type == "workspace_snapshot_import"
               )
             )

    assert dedupe_key == "workspace_snapshot_import:#{accepted.id}:failure"

    assert Enum.any?(Repo.all(StorageCleanupRequest), fn request ->
             MapSet.subset?(
               MapSet.new(accepted.staging_storage_keys),
               MapSet.new(request.storage_keys)
             )
           end)
  end

  test "reimporting the same terminal ZIP uses disjoint staging and materialization namespaces", context do
    asset_bytes = "repeatable import bytes"
    _asset = upload_asset!(context.project, context.user, "repeat.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, first_accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "repeat.zip"}
             )

    assert :ok = first_accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()
    first = Repo.get!(WorkspaceSnapshotImport, first_accepted.id)
    assert first.status == "completed"

    assert Enum.any?(Repo.all(StorageCleanupRequest), fn request ->
             first.archive_storage_key in request.storage_keys
           end)

    assert {:ok, second_accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "repeat-again.zip"}
             )

    assert second_accepted.id != first.id
    assert second_accepted.archive_storage_key != first.archive_storage_key

    assert MapSet.disjoint?(
             MapSet.new(second_accepted.staging_storage_keys),
             MapSet.new(first.staging_storage_keys)
           )

    assert :ok = second_accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()
    second = Repo.get!(WorkspaceSnapshotImport, second_accepted.id)
    assert second.status == "completed"
    assert second.project_id != first.project_id

    assert MapSet.disjoint?(
             MapSet.new(second.materialization_storage_keys),
             MapSet.new(first.materialization_storage_keys)
           )

    assert import_notification_count(context.user.id) == 2
  end

  test "workspace hard delete is rejected while an import is active", context do
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "active.zip"}
             )

    assert {:error, :workspace_snapshot_import_in_progress} =
             Workspaces.delete_workspace(context.workspace)

    assert Repo.get!(WorkspaceSnapshotImport, accepted.id).status == "queued"
    assert Repo.get!(Workspace, context.workspace.id)
    assert Repo.get!(Project, context.project.id)
    assert {:ok, %{size: size}} = Storage.stat(accepted.archive_storage_key)
    assert size == accepted.archive_size_bytes
  end

  test "a downloaded canonical ZIP alone reconstructs a hard-deleted project exactly", context do
    source_project = context.project
    source_project_id = source_project.id
    referenced_bytes = "referenced voice bytes"
    unreferenced_bytes = "unreferenced but recoverable bytes"

    source_language_fixture(source_project, %{locale_code: "en", name: "English"})
    language_fixture(source_project, %{locale_code: "es", name: "Spanish"})

    sheet = sheet_fixture(source_project, %{name: "Hero"})

    _block =
      block_fixture(sheet, %{
        type: "rich_text",
        variable_name: "biography",
        value: %{"content" => "A hero restored from a standalone ZIP"}
      })

    referenced_asset =
      upload_asset!(
        source_project,
        context.user,
        "voice.mp3",
        referenced_bytes,
        "audio/mpeg"
      )

    unreferenced_asset =
      upload_asset!(
        source_project,
        context.user,
        "unused.png",
        unreferenced_bytes,
        "image/png"
      )

    flow = flow_fixture(source_project, %{name: "Opening"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker" => "Narrator",
          "text" => "The archive remembers.",
          "audio_asset_id" => referenced_asset.id
        }
      })

    assert [localized] = Localization.get_texts_for_source("flow_node", node.id)

    assert {:ok, _localized} =
             Localization.update_text(localized, %{
               translated_text: "El archivo recuerda.",
               status: "final"
             })

    scene = scene_fixture(source_project, %{name: "World map", description: "Authored scene"})

    _pin =
      pin_fixture(scene, %{
        "label" => "Hero entrance",
        "tooltip" => "Launch the opening flow",
        "sheet_id" => sheet.id,
        "flow_id" => flow.id
      })

    _annotation =
      annotation_fixture(scene, %{
        "text" => "Keep this authored scene note",
        "position_x" => 20.0,
        "position_y" => 30.0
      })

    snapshot = build_ready_snapshot!(context.scope, source_project)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    archive_path = temporary_archive_path!(archive)

    original_provider_keys = [
      snapshot.archive_storage_key,
      snapshot.manifest_storage_key,
      referenced_asset.key,
      unreferenced_asset.key,
      protected_blob_key(referenced_asset),
      protected_blob_key(unreferenced_asset)
    ]

    assert {:ok, soft_deleted} = Projects.delete_project(source_project, context.user.id)
    assert {:ok, _hard_deleted} = Projects.permanently_delete_project(soft_deleted)

    Enum.each(original_provider_keys, fn key ->
      assert :ok = Storage.adapter().delete(key)
      assert {:error, :enoent} = Storage.stat(key)
    end)

    refute Repo.get(Project, source_project_id)

    snapshot_count =
      Repo.aggregate(
        from(snapshot in ProjectSnapshot, where: snapshot.project_id == ^source_project_id),
        :count
      )

    assert snapshot_count == 0

    assert Repo.aggregate(from(asset in Asset, where: asset.project_id == ^source_project_id), :count) == 0

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "standalone-recovery.zip"}
             )

    assert accepted.reserved_bytes == byte_size(referenced_bytes) + byte_size(unreferenced_bytes)
    assert :ok = accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()

    completed = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    recovered = Repo.get!(Project, completed.project_id)

    assert completed.status == "completed"
    assert completed.stage == "completed"
    assert completed.progress_bytes == completed.progress_total_bytes
    assert completed.reserved_bytes == 0
    assert recovered.id != source_project_id
    assert recovered.workspace_id == context.workspace.id
    assert recovered.name == source_project.name
    assert recovered.description == source_project.description
    assert recovered.project_type == source_project.project_type
    assert recovered.project_subtype == source_project.project_subtype
    assert recovered.project_type_other == source_project.project_type_other
    assert recovered.settings == source_project.settings
    assert recovered.auto_version_flows == source_project.auto_version_flows
    assert recovered.auto_version_scenes == source_project.auto_version_scenes
    assert recovered.auto_version_sheets == source_project.auto_version_sheets

    assert %{role: "owner"} = Projects.get_membership(recovered.id, context.user.id)

    assert [recovered_sheet] = Storyarn.Sheets.list_all_sheets(recovered.id)
    assert recovered_sheet.name == "Hero"
    assert [recovered_block] = Storyarn.Sheets.list_blocks(recovered_sheet.id)
    assert recovered_block.variable_name == "biography"
    assert recovered_block.value == %{"content" => "A hero restored from a standalone ZIP"}

    assert [recovered_flow] = Flows.list_flows(recovered.id)
    assert recovered_flow.name == "Opening"
    recovered_node = Enum.find(Flows.list_nodes(recovered_flow.id), &(&1.type == "dialogue"))
    assert recovered_node
    assert recovered_node.data["text"] == "The archive remembers."

    assert [recovered_scene] = Scenes.list_scenes(recovered.id)
    assert recovered_scene.name == "World map"
    assert recovered_scene.description == "Authored scene"
    assert [recovered_pin] = Scenes.list_pins(recovered_scene.id)
    assert recovered_pin.label == "Hero entrance"
    assert recovered_pin.tooltip == "Launch the opening flow"
    assert recovered_pin.sheet_id == recovered_sheet.id
    assert recovered_pin.flow_id == recovered_flow.id
    assert [recovered_annotation] = Scenes.list_annotations(recovered_scene.id)
    assert recovered_annotation.text == "Keep this authored scene note"

    assert Enum.map(Localization.list_languages(recovered.id), &{&1.locale_code, &1.is_source}) == [
             {"en", true},
             {"es", false}
           ]

    recovered_text =
      Enum.find(
        Localization.list_texts_for_export(recovered.id, ["es"]),
        &(&1.source_type == "flow_node" and &1.source_field == "text")
      )

    assert recovered_text
    assert recovered_text.source_text == "The archive remembers."
    assert recovered_text.translated_text == "El archivo recuerda."
    assert recovered_text.status == "final"

    recovered_assets = Assets.list_assets(recovered.id)
    assert Enum.sort(Enum.map(recovered_assets, & &1.filename)) == ["unused.png", "voice.mp3"]

    for {filename, expected_bytes} <- [
          {"voice.mp3", referenced_bytes},
          {"unused.png", unreferenced_bytes}
        ] do
      recovered_asset = Enum.find(recovered_assets, &(&1.filename == filename))
      assert {:ok, ^expected_bytes} = Storage.download(recovered_asset.key)
      assert {:ok, ^expected_bytes} = Storage.download(protected_blob_key(recovered_asset))
    end

    recovered_voice = Enum.find(recovered_assets, &(&1.filename == "voice.mp3"))
    assert recovered_node.data["audio_asset_id"] == recovered_voice.id

    usage = Billing.workspace_storage_usage(context.workspace.id)
    expected_asset_bytes = byte_size(referenced_bytes) + byte_size(unreferenced_bytes)
    assert usage.current_assets == %{bytes: expected_asset_bytes, count: 2}
    assert usage.active_reservations.by_kind == %{}
    assert usage.accounted_bytes == expected_asset_bytes

    assert [notification] =
             Repo.all(
               from(notification in Notification,
                 where:
                   notification.recipient_id == ^context.user.id and
                     notification.entity_type == "workspace_snapshot_import" and
                     notification.entity_id == ^accepted.id
               )
             )

    assert notification.status == "success"
    assert notification.project_id == recovered.id
    assert notification.dedupe_key == "workspace_snapshot_import:#{accepted.id}:success"

    assert {:ok, deleted_recovered} = Projects.delete_project(recovered, context.user.id)
    assert {:ok, _hard_deleted_recovered} = Projects.permanently_delete_project(deleted_recovered)

    historical_import = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert historical_import.status == "completed"
    assert historical_import.project_id == nil
  end

  test "workspace authorization is enforced before an archive can be admitted", context do
    archive_path = ready_archive_file!(context.scope, context.project)
    intruder = user_fixture()
    intruder_scope = user_scope_fixture(intruder)

    assert {:error, :not_found} =
             Versioning.request_workspace_snapshot_import(
               intruder_scope,
               context.workspace,
               archive_path,
               %{original_filename: "foreign.zip"}
             )

    assert Versioning.list_workspace_snapshot_imports(intruder_scope, context.workspace) == []
    assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 0
    assert import_job_count() == 0
  end

  test "concurrent workspace role revocation fences both admission and final publication" do
    fixture = committed_authorization_fixture!()
    on_exit(fn -> cleanup_committed_authorization_fixture(fixture) end)

    admission_revoker =
      hold_role_revocation(fixture.admission_membership.id, self(), :admission)

    assert_receive {:role_revocation_pending, :admission, admission_revoker_pid, admission_revoker_backend},
                   @concurrency_timeout

    admission_requester =
      unboxed_task(fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(self_test_process(), {:import_request_started, self(), backend_pid})

        Versioning.request_workspace_snapshot_import(
          fixture.admission_scope,
          fixture.workspace,
          fixture.archive_path,
          %{original_filename: "authorization-race.zip"}
        )
      end)

    assert_receive {:import_request_started, admission_requester_pid, admission_requester_backend},
                   @concurrency_timeout

    assert admission_requester_pid == admission_requester.pid

    assert_eventually_blocked_by(
      admission_requester_backend,
      admission_revoker_backend,
      admission_requester
    )

    refute Task.yield(admission_requester, 0)
    send(admission_revoker_pid, {:release_role_revocation, :admission})

    assert %WorkspaceMembership{role: "viewer"} = Task.await(admission_revoker, @concurrency_timeout)

    assert {:error, :unauthorized} = Task.await(admission_requester, @concurrency_timeout)

    assert Sandbox.unboxed_run(Repo, fn ->
             Repo.aggregate(
               from(import in WorkspaceSnapshotImport,
                 where: import.workspace_id == ^fixture.workspace.id
               ),
               :count
             )
           end) == 0

    accepted =
      Sandbox.unboxed_run(Repo, fn ->
        assert {:ok, accepted} =
                 Versioning.request_workspace_snapshot_import(
                   fixture.publication_scope,
                   fixture.workspace,
                   fixture.archive_path,
                   %{original_filename: "publication-authorization-race.zip"}
                 )

        accepted
      end)

    job = Sandbox.unboxed_run(Repo, fn -> import_job!(accepted) end)

    publication_revoker =
      hold_role_revocation(fixture.publication_membership.id, self(), :publication)

    assert_receive {:role_revocation_pending, :publication, publication_revoker_pid, publication_revoker_backend},
                   @concurrency_timeout

    publication_runner =
      unboxed_task(fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(self_test_process(), {:import_publication_started, self(), backend_pid})

        Versioning.perform_workspace_snapshot_import(
          accepted.id,
          job_id: job.id,
          attempt: 1,
          max_attempts: ImportProjectSnapshotWorker.max_attempts()
        )
      end)

    assert_receive {:import_publication_started, publication_runner_pid, publication_runner_backend},
                   @concurrency_timeout

    assert publication_runner_pid == publication_runner.pid

    assert_eventually_blocked_by(
      publication_runner_backend,
      publication_revoker_backend,
      publication_runner
    )

    send(publication_revoker_pid, {:release_role_revocation, :publication})

    assert %WorkspaceMembership{role: "viewer"} = Task.await(publication_revoker, @concurrency_timeout)

    assert {:ok, %WorkspaceSnapshotImport{status: "failed"} = failed} =
             Task.await(publication_runner, @concurrency_timeout)

    assert failed.project_id == nil
    assert failed.reserved_bytes == 0

    assert Sandbox.unboxed_run(Repo, fn ->
             Repo.aggregate(
               from(project in Project, where: project.workspace_id == ^fixture.workspace.id),
               :count
             )
           end) == 1
  end

  defp ready_archive_file!(scope, project) do
    snapshot = build_ready_snapshot!(scope, project)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    temporary_archive_path!(archive)
  end

  defp committed_authorization_fixture! do
    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        owner = user_fixture(%{email: "snapshot-auth-owner-#{Ecto.UUID.generate()}@example.com"})
        admission_user = user_fixture(%{email: "snapshot-auth-admission-#{Ecto.UUID.generate()}@example.com"})
        publication_user = user_fixture(%{email: "snapshot-auth-publication-#{Ecto.UUID.generate()}@example.com"})
        workspace = workspace_fixture(owner)
        project = project_fixture(owner, %{workspace: workspace, name: "Authorization race source"})

        assert {:ok, admission_membership} =
                 Workspaces.create_membership(workspace.id, admission_user.id, "admin")

        assert {:ok, publication_membership} =
                 Workspaces.create_membership(workspace.id, publication_user.id, "admin")

        owner_scope = user_scope_fixture(owner)
        snapshot = build_ready_snapshot!(owner_scope, project)
        assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)

        %{
          owner: owner,
          admission_user: admission_user,
          admission_scope: user_scope_fixture(admission_user),
          admission_membership: admission_membership,
          publication_user: publication_user,
          publication_scope: user_scope_fixture(publication_user),
          publication_membership: publication_membership,
          workspace: workspace,
          project: project,
          source_snapshot: snapshot,
          archive: archive
        }
      end)

    Map.put(fixture, :archive_path, temporary_archive_path!(fixture.archive))
  end

  defp hold_role_revocation(membership_id, test_process, marker) do
    unboxed_task(fn ->
      fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        membership = Repo.get!(WorkspaceMembership, membership_id)
        assert {:ok, updated} = Workspaces.update_member_role(membership, "viewer")
        send(test_process, {:role_revocation_pending, marker, self(), backend_pid})

        receive do
          {:release_role_revocation, ^marker} -> updated
        after
          @concurrency_timeout * 2 -> exit(:workspace_role_revocation_release_timeout)
        end
      end
      |> Repo.transaction()
      |> case do
        {:ok, updated} -> updated
        {:error, reason} -> exit({:workspace_role_revocation_failed, reason})
      end
    end)
  end

  defp unboxed_task(fun) do
    test_process = self()

    Task.async(fn ->
      Process.put({__MODULE__, :test_process}, test_process)
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        fun.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp self_test_process, do: Process.get({__MODULE__, :test_process})

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, task, attempts \\ 500)

  defp assert_eventually_blocked_by(_waiter_backend_pid, _holder_backend_pid, _task, 0) do
    flunk("workspace snapshot import never waited on the locked membership")
  end

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, task, attempts) do
    blocked? =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT $2 = ANY(pg_blocking_pids($1))", [waiter_backend_pid, holder_backend_pid]).rows == [[true]]
      end)

    if blocked? do
      :ok
    else
      case Task.yield(task, 0) do
        nil ->
          Process.sleep(@concurrency_poll_interval)
          assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, task, attempts - 1)

        {:ok, result} ->
          flunk("workspace snapshot import finished before the membership lock: #{inspect(result)}")
      end
    end
  end

  defp cleanup_committed_authorization_fixture(fixture) do
    storage_keys =
      Sandbox.unboxed_run(Repo, fn ->
        imports =
          Repo.all(
            from(import in WorkspaceSnapshotImport,
              where: import.workspace_id == ^fixture.workspace.id
            )
          )

        storage_keys =
          imports
          |> Enum.flat_map(&(&1.staging_storage_keys ++ &1.materialization_storage_keys))
          |> Kernel.++([
            fixture.source_snapshot.archive_storage_key,
            fixture.source_snapshot.manifest_storage_key
          ])
          |> Enum.uniq()

        cleanup_requests =
          StorageCleanupRequest
          |> Repo.all()
          |> Enum.filter(fn request ->
            Enum.any?(request.storage_keys, &String.starts_with?(&1, import_prefix(fixture.workspace.id)))
          end)

        Enum.each(cleanup_requests, &Repo.delete!/1)

        user_ids = [fixture.owner.id, fixture.admission_user.id, fixture.publication_user.id]
        Repo.delete_all(from(workspace in Workspace, where: workspace.owner_id in ^user_ids))

        job_ids =
          imports
          |> Enum.map(& &1.oban_job_id)
          |> Kernel.++([fixture.source_snapshot.build_job_id])
          |> Enum.reject(&is_nil/1)

        Repo.delete_all(from(job in Oban.Job, where: job.id in ^job_ids))

        Repo.delete_all(from(user in User, where: user.id in ^user_ids))
        storage_keys
      end)

    storage = Storage.adapter()
    Enum.each(storage_keys, &storage.delete/1)
  end

  defp build_ready_snapshot!(scope, project) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(scope, project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert :ok = BuildProjectSnapshotWorker.perform(job)
    Versioning.get_project_snapshot(project.id, requested.id)
  end

  defp import_job!(import) do
    import.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Map.put(:attempt, 1)
    |> Map.put(:max_attempts, ImportProjectSnapshotWorker.max_attempts())
  end

  defp mark_import_job_discarded!(import) do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}

    import.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "discarded",
      attempt: ImportProjectSnapshotWorker.max_attempts(),
      discarded_at: now
    )
    |> Repo.update!()
  end

  defp import_cleanup_requests(import) do
    StorageCleanupRequest
    |> Repo.all()
    |> Enum.filter(&(import.archive_storage_key in &1.storage_keys))
  end

  defp import_notifications(import) do
    Repo.all(
      from(notification in Notification,
        where:
          notification.recipient_id == ^import.user_id and
            notification.entity_type == "workspace_snapshot_import" and
            notification.entity_id == ^import.id
      )
    )
  end

  defp upload_asset!(project, user, filename, bytes, content_type) do
    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               bytes,
               %{filename: filename, content_type: content_type},
               project,
               user
             )

    on_exit(fn ->
      Storage.adapter().delete(asset.key)
      Storage.adapter().delete(protected_blob_key(asset))
    end)

    asset
  end

  defp temporary_archive_path!(archive) do
    path = Path.join(System.tmp_dir!(), "storyarn-workspace-import-#{Ecto.UUID.generate()}.zip")
    File.write!(path, archive, [:binary])
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp protected_blob_key(asset) do
    BlobStore.blob_key(
      asset.project_id,
      asset.blob_hash,
      BlobStore.ext_from_content_type(asset.content_type)
    )
  end

  defp corrupt_first_byte(<<first, rest::binary>>), do: <<Bitwise.bxor(first, 1), rest::binary>>

  defp import_job_count do
    Repo.aggregate(
      from(job in Oban.Job, where: job.worker == ^inspect(ImportProjectSnapshotWorker)),
      :count
    )
  end

  defp import_notification_count(user_id) do
    Repo.aggregate(
      from(notification in Notification,
        where:
          notification.recipient_id == ^user_id and
            notification.entity_type == "workspace_snapshot_import"
      ),
      :count
    )
  end

  defp import_prefix(workspace_id), do: "workspaces/#{workspace_id}/snapshot-imports/v1/"
end
