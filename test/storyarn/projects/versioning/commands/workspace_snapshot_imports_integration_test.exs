defmodule Storyarn.Projects.Versioning.WorkspaceSnapshotImportsIntegrationTest do
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

  alias Storyarn.Commercial.Billing
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImports
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.ImportProjectSnapshotWorker

  defmodule DirectUploadStorage do
    @moduledoc false
    def presigned_upload_url(key, content_type, _opts),
      do: {:ok, "https://uploads.example/#{key}", %{headers: %{"content-type" => content_type}}}
  end

  defmodule RaisingDirectUploadStorage do
    @moduledoc false
    def presigned_upload_url(_key, _content_type, _opts), do: raise("presign failure")
  end

  defmodule ThrowingDirectUploadStorage do
    @moduledoc false
    def presigned_upload_url(_key, _content_type, _opts), do: throw(:presign_failure)
  end

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

    {_direct, upload} = prepare_stored_upload!(context, archive_path, "too-large.zip")

    assert {:error, :limit_reached, details} =
             WorkspaceSnapshotImports.request_stored(context.scope, context.workspace, upload.id)

    assert details.required_bytes > 0
    assert details.available_bytes == 0
    assert details.limit_bytes == limit
    assert Repo.aggregate(WorkspaceSnapshotImport, :count) == import_count
    assert import_job_count() == job_count
    assert import_notification_count(context.user.id) == notification_count

    assert Billing.workspace_storage_usage(context.workspace.id).active_reservations.by_kind[
             "workspace_snapshot_import"
           ] in [nil, 0]

    assert [%StorageCleanupRequest{storage_keys: [archive_key], multipart_quiescence_not_before: not_before}] =
             Repo.all(StorageCleanupRequest)

    assert String.starts_with?(archive_key, import_prefix(context.workspace.id))
    assert {:error, :enoent} = Storage.stat(archive_key)
    assert DateTime.after?(not_before, TimeHelpers.now())
  end

  test "direct request is durable and duplicate job delivery is idempotent", context do
    asset_bytes = "durable snapshot asset"
    _asset = upload_asset!(context.project, context.user, "durable.png", asset_bytes, "image/png")
    archive_path = ready_archive_file!(context.scope, context.project)

    {_direct, upload} = prepare_stored_upload!(context, archive_path, "durable.zip")
    assert {:ok, first} = WorkspaceSnapshotImports.request_stored(context.scope, context.workspace, upload.id)

    assert import_job_count() == 1
    assert first.status == "queued"
    assert first.reserved_bytes == byte_size(asset_bytes)
    assert first.oban_job_id

    usage = Billing.workspace_storage_usage(context.workspace.id)
    assert usage.active_reservations.by_kind["workspace_snapshot_import"] == byte_size(asset_bytes)

    job = import_job!(first)

    assert {:discard, :workspace_snapshot_import_job_mismatch} =
             Versioning.perform_workspace_snapshot_import(first.id,
               job_id: job.id + 1,
               attempt: 1,
               max_attempts: job.max_attempts
             )

    assert Repo.get!(WorkspaceSnapshotImport, first.id).status == "queued"
    assert :ok = ImportProjectSnapshotWorker.perform(job)
    assert :ok = ImportProjectSnapshotWorker.perform(job)

    completed = Repo.get!(WorkspaceSnapshotImport, first.id)
    assert completed.status == "completed"
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

  test "imports a maximum-length visible asset filename through a bounded physical key", context do
    filename = String.duplicate("a", 251) <> ".png"
    asset_bytes = "maximum filename snapshot asset"

    context.project
    |> upload_asset!(context.user, "source.png", asset_bytes, "image/png")
    |> Ecto.Changeset.change(filename: filename)
    |> Repo.update!()

    assert byte_size(filename) == 255
    archive_path = ready_archive_file!(context.scope, context.project)

    assert {:ok, accepted} =
             Versioning.request_workspace_snapshot_import(
               context.scope,
               context.workspace,
               archive_path,
               %{original_filename: "maximum-asset-filename.zip"}
             )

    assert :ok = accepted |> import_job!() |> ImportProjectSnapshotWorker.perform()

    completed = Repo.get!(WorkspaceSnapshotImport, accepted.id)
    assert [recovered_asset] = Assets.list_assets(completed.project_id)

    assert completed.status == "completed"
    assert recovered_asset.filename == filename
    assert byte_size(recovered_asset.key) <= 255
    assert String.ends_with?(recovered_asset.key, "/#{recovered_asset.blob_hash}.png")
    refute String.ends_with?(recovered_asset.key, "/#{filename}")
    assert Enum.all?(completed.materialization_storage_keys, &(byte_size(&1) <= 255))
    assert {:ok, ^asset_bytes} = Storage.download(recovered_asset.key)
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
    assert failed.failure_code == "snapshot_zip_local_header_mismatch"

    assert [%Notification{status: "failure"}] = import_notifications(failed)

    assert Enum.any?(Repo.all(StorageCleanupRequest), fn request ->
             MapSet.subset?(
               MapSet.new(accepted.staging_storage_keys),
               MapSet.new(request.storage_keys)
             )
           end)
  end

  test "cancel and TTL remove direct-upload owners without jobs or notifications", context do
    archive_path = ready_archive_file!(context.scope, context.project)
    {_direct, upload} = prepare_stored_upload!(context, archive_path, "cancel.zip")

    assert {:error, :workspace_snapshot_import_in_progress} =
             Versioning.prepare_external_workspace_snapshot_import(context.scope, context.workspace, %{
               original_filename: "blocked.zip",
               archive_size_bytes: File.stat!(archive_path).size
             })

    admin = user_fixture()
    workspace_membership_fixture(context.workspace, admin, "admin")

    assert {:ok, _deleted} =
             Versioning.cancel_workspace_snapshot_upload(user_scope_fixture(admin), context.workspace, upload.id)

    refute Repo.get(WorkspaceSnapshotImport, upload.id)
    archive_key = upload.archive_storage_key
    assert [%StorageCleanupRequest{storage_keys: [^archive_key]}] = Repo.all(StorageCleanupRequest)
    assert import_job_count() == 0

    {_direct, stale} = prepare_stored_upload!(context, archive_path, "stale.zip")

    Repo.update_all(from(import in WorkspaceSnapshotImport, where: import.id == ^stale.id),
      set: [updated_at: ~U[2020-01-01 00:00:00Z]]
    )

    assert %{changed_count: 1, failure_count: 0} =
             Versioning.reconcile_abandoned_workspace_snapshot_import_deliveries(upload_ttl_seconds: 1)

    refute Repo.get(WorkspaceSnapshotImport, stale.id)
    assert import_job_count() == 0
    assert import_notification_count(context.user.id) == 0
  end

  test "cancelled direct uploads exhaust the bounded grant window", context do
    prepare = fn ->
      WorkspaceSnapshotImports.prepare_external_upload(
        context.scope,
        context.workspace,
        %{original_filename: "cancel.zip", archive_size_bytes: 1},
        storage: DirectUploadStorage
      )
    end

    Enum.each(1..3, fn _attempt ->
      assert {:ok, %{import_id: import_id}} = prepare.()
      assert {:ok, _upload} = WorkspaceSnapshotImports.cancel_upload(context.scope, context.workspace, import_id)
    end)

    assert {:error, :workspace_snapshot_upload_rate_limited} = prepare.()

    assert Repo.aggregate(StorageCleanupRequest, :count) == 3

    assert {:ok, local} =
             WorkspaceSnapshotImports.prepare_upload(context.scope, context.workspace, %{
               original_filename: "local.zip",
               archive_size_bytes: 1
             })

    assert {:ok, _upload} = WorkspaceSnapshotImports.cancel_upload(context.scope, context.workspace, local.id)
    assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 0
    assert import_job_count() == 0
    assert import_notification_count(context.user.id) == 0
  end

  test "presign crashes discard the direct-upload owner durably", context do
    Enum.each([RaisingDirectUploadStorage, ThrowingDirectUploadStorage], fn storage ->
      assert {:error, :snapshot_import_unavailable} =
               WorkspaceSnapshotImports.prepare_external_upload(
                 context.scope,
                 context.workspace,
                 %{original_filename: "crash.zip", archive_size_bytes: 1},
                 storage: storage
               )

      assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 0
    end)

    assert Repo.aggregate(StorageCleanupRequest, :count) == 2
    assert import_job_count() == 0
    assert import_notification_count(context.user.id) == 0
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
      assert :ok = ObjectStorage.delete(key)
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

  defp ready_archive_file!(scope, project) do
    snapshot = build_ready_snapshot!(scope, project)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    temporary_archive_path!(archive)
  end

  defp prepare_stored_upload!(context, archive_path, filename) do
    assert {:ok, direct} =
             WorkspaceSnapshotImports.prepare_external_upload(
               context.scope,
               context.workspace,
               %{original_filename: filename, archive_size_bytes: File.stat!(archive_path).size},
               storage: DirectUploadStorage
             )

    upload = Repo.get!(WorkspaceSnapshotImport, direct.import_id)
    assert upload.status == "uploading"
    assert {:ok, _url} = Storage.upload(upload.archive_storage_key, File.read!(archive_path), "application/zip")
    {direct, upload}
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
      ObjectStorage.delete(asset.key)
      ObjectStorage.delete(protected_blob_key(asset))
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
    worker = inspect(ImportProjectSnapshotWorker)

    Repo.aggregate(
      from(job in Oban.Job,
        where: job.worker == ^worker
      ),
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

  defp import_prefix(workspace_id), do: "workspace-snapshot-imports/v1/#{workspace_id}/"
end
