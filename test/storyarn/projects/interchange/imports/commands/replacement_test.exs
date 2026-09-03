defmodule Storyarn.Projects.Imports.ReplacementTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Localization
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Imports.Replacement
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.Versioning.EntityVersionRecord, as: EntityVersion
  alias Storyarn.SnapshotReadSwitchStorage

  @yarn_project_fixture_root Path.expand("../../../../../fixtures/imports/yarn/emberfall", __DIR__)
  @yarn_project_fixture_files [
    "Emberfall.yarnproject",
    "Dialogue/01_arrival.yarn",
    "Dialogue/02_market.yarn",
    "Dialogue/03_watchtower.yarn"
  ]

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{scope: Scope.for_user(user), user: user, project: project}
  end

  test "Storyarn-owned multi-file Yarn project is eligible for whole-project replacement" do
    assert {:ok, %ImportPlan{} = plan} =
             Imports.parse_file("emberfall.zip", yarn_project_fixture_archive())

    assert plan.parser_version == "6"
    assert plan.source_kind == :archive
    assert plan.replace_eligible
    assert plan.issues == []

    flows = Map.new(plan.data["flows"], &{&1["name"], &1})
    assert flows |> Map.keys() |> Enum.sort() == ["Arrival", "Market", "Watchtower"]
    refute Enum.any?(flows, fn {_name, flow} -> flow["is_main"] end)

    variables_sheet = Enum.find(plan.data["sheets"], &(&1["shortcut"] == "yarn"))

    assert variables_sheet["blocks"]
           |> Enum.map(& &1["variable_name"])
           |> Enum.sort() == ["has_watch_map", "mara_trust", "watch_alerted"]

    speaker_names = MapSet.new(plan.data["sheets"], & &1["name"])

    assert MapSet.subset?(
             MapSet.new(["Captain Ilyra", "Mara", "Narrator", "Player", "Tarin"]),
             speaker_names
           )

    arrival_targets =
      flows["Arrival"]["nodes"]
      |> Enum.filter(&(&1["type"] == "exit"))
      |> MapSet.new(& &1["data"]["referenced_flow_id"])

    assert arrival_targets ==
             MapSet.new([flows["Market"]["id"], flows["Watchtower"]["id"]])
  end

  test "confirmed replacement queues durably without creating a snapshot in the request", ctx do
    snapshot_count = Repo.aggregate(ProjectSnapshot, :count)
    assert {:ok, ready} = ready_replacement(ctx)

    assert {:error, :replace_import_confirmation_required} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename, import_mode: "replace_project")

    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("enqueue must not request the recovery snapshot")
               end
             )

    assert queued.status == "queued"
    assert queued.stage == "awaiting_snapshot"
    assert queued.pre_import_snapshot_id == nil
    assert Repo.aggregate(ProjectSnapshot, :count) == snapshot_count
  end

  test "snapshot-backed replacement completes without runtime gates", ctx do
    assert {:ok, prepared, _preview} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               "available-replacement.zip",
               replaceable_yarn_archive()
             )

    assert prepared.replace_eligible
    assert {:ok, ready} = Imports.update_import_mode(ctx.scope, prepared.id, "replace_project")

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    assert {:ok, completed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: ready_snapshot_request(ctx, current_project_checksum(ctx.project))
             )

    assert completed.status == "completed"
  end

  test "the database fence rejects a legacy completion before replacement preparation", ctx do
    assert {:ok, queued_attempt} = queued_replacement(ctx)
    queued = Repo.preload(queued_attempt, :user)

    assert {:ok, bound} =
             Replacement.ensure_snapshot_ready(
               queued,
               ctx.project,
               snapshot_request: ready_snapshot_request(ctx, current_project_checksum(ctx.project))
             )

    assert {:ok, running} =
             bound
             |> ProjectImportAttempt.running_changeset(TimeHelpers.now())
             |> Repo.update()

    assert {:error, changeset} =
             running
             |> ProjectImportAttempt.completed_changeset(TimeHelpers.now(), %{})
             |> Repo.update()

    assert Keyword.has_key?(changeset.errors, :replacement_prepared_at)
    assert Repo.get!(ProjectImportAttempt, running.id).status == "running"

    assert {:error, stale_fence_changeset} =
             running
             |> Ecto.Changeset.change(replacement_prepared_at: TimeHelpers.now())
             |> Ecto.Changeset.check_constraint(:replacement_prepared_at,
               name: :project_import_attempts_replacement_fence_check
             )
             |> Repo.update()

    assert Keyword.has_key?(stale_fence_changeset.errors, :replacement_prepared_at)
  end

  test "a transient snapshot request remains queued, cancellable, and resumes", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    assert {:error, :retryable_import_error} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: fn _scope, _project, _attrs -> {:error, :backend_down} end
             )

    retryable = Repo.get!(ProjectImportAttempt, queued.id)
    assert retryable.status == "queued"
    assert retryable.stage == "awaiting_snapshot"
    assert retryable.error_code == "pre_import_snapshot_request_failed"

    snapshot_request = fn scope, project, attrs ->
      {:ok,
       pending_project_snapshot_fixture(project, %{
         created_by_id: scope.user.id,
         idempotency_key: attrs.idempotency_key
       })}
    end

    assert {:snooze, 5} =
             Imports.perform_import(queued.id,
               attempt: 2,
               max_attempts: 3,
               snapshot_request: snapshot_request
             )

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    assert waiting.status == "queued"
    assert waiting.stage == "awaiting_snapshot"
    assert waiting.error_code == nil
    assert %DateTime{} = waiting.snapshot_reference_bound_at
  end

  test "snapshot request exceptions report their sanitized module without leaking details", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    handler_id = "replacement-snapshot-request-exception-#{System.unique_integer([:positive])}"
    marker = make_ref()
    private_detail = "customer-private-snapshot-request-detail"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn event, measurements, metadata, {pid, ref} ->
          send(pid, {ref, event, measurements, metadata})
        end,
        {parent, marker}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, :retryable_import_error} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: fn _scope, _project, _attrs ->
                 raise ArgumentError, private_detail
               end
             )

    assert_receive {^marker, [:storyarn, :import, :error], %{count: 1}, metadata}
    assert metadata.error_code == "pre_import_snapshot_request_failed"
    assert metadata.exception_module == "ArgumentError"
    refute inspect(metadata) =~ private_detail
  end

  test "transient plan loads recover before and after a pending snapshot is bound", ctx do
    assert {:ok, before_request} = queued_replacement(ctx, "before-request.zip")

    assert {:error, :retryable_import_error} =
             Imports.perform_import(before_request.id,
               attempt: 1,
               max_attempts: 3,
               plan_load: fn _key -> {:error, :backend_down} end,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("plan loading must finish before requesting a snapshot")
               end
             )

    assert %{status: "queued", stage: "awaiting_snapshot"} =
             Repo.get!(ProjectImportAttempt, before_request.id)

    assert {:snooze, 5} =
             Imports.perform_import(before_request.id,
               attempt: 2,
               max_attempts: 3,
               snapshot_request: fn scope, project, attrs ->
                 {:ok,
                  pending_project_snapshot_fixture(project, %{
                    created_by_id: scope.user.id,
                    idempotency_key: attrs.idempotency_key
                  })}
               end
             )

    assert {:ok, after_binding} = queued_replacement(ctx, "after-binding.zip")

    pending_request = fn scope, project, attrs ->
      {:ok,
       pending_project_snapshot_fixture(project, %{
         created_by_id: scope.user.id,
         idempotency_key: attrs.idempotency_key
       })}
    end

    assert {:snooze, 5} =
             Imports.perform_import(after_binding.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: pending_request
             )

    assert {:error, :retryable_import_error} =
             Imports.perform_import(after_binding.id,
               attempt: 1,
               max_attempts: 3,
               plan_load: fn _key -> {:error, :backend_down} end,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("a bound snapshot must never be requested again")
               end
             )

    assert {:snooze, 5} =
             Imports.perform_import(after_binding.id,
               attempt: 2,
               max_attempts: 3,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("the pending snapshot reference must be reused")
               end
             )

    assert %{status: "queued", stage: "awaiting_snapshot", error_code: nil} =
             Repo.get!(ProjectImportAttempt, after_binding.id)
  end

  test "the worker binds one pending snapshot and snoozes without consuming an import retry", ctx do
    assert {:ok, queued} = queued_replacement(ctx)
    test_pid = self()

    snapshot_request = fn scope, project, attrs ->
      send(test_pid, {:snapshot_requested, scope.user.id, attrs})

      {:ok,
       pending_project_snapshot_fixture(project, %{
         created_by_id: scope.user.id,
         idempotency_key: attrs.idempotency_key
       })}
    end

    assert {:snooze, 5} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: snapshot_request
             )

    assert_receive {:snapshot_requested, user_id, attrs}
    assert user_id == ctx.user.id
    assert attrs.idempotency_key == queued.snapshot_request_key
    assert attrs.title == "Before Yarn project replacement"
    assert attrs.description == "Recovery point created before replacing narrative project content."
    refute inspect(attrs) =~ "replaceable-yarn.zip"

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    assert waiting.status == "queued"
    assert waiting.stage == "awaiting_snapshot"
    assert is_integer(waiting.pre_import_snapshot_id)
    assert waiting.error_code == nil

    assert {:snooze, 5} =
             Imports.perform_import(waiting.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("a bound snapshot must be reused")
               end
             )
  end

  test "cancelling a replacement cancels and durably cleans its pending recovery snapshot", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    assert {:snooze, _seconds} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3
             )

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    snapshot_id = waiting.pre_import_snapshot_id
    assert is_integer(snapshot_id)
    assert Repo.get!(ProjectSnapshot, snapshot_id).lifecycle_state == "pending"

    assert {:ok, expired} = Imports.cancel_import(ctx.scope, waiting.id)
    assert expired.status == "expired"
    assert expired.pre_import_snapshot_id == nil
    refute Repo.get(ProjectSnapshot, snapshot_id)

    assert %SnapshotCleanupIntent{
             reason: "abandoned_import",
             authority_kind: "system",
             authority_actor_id: nil
           } =
             Repo.get_by!(SnapshotCleanupIntent,
               project_snapshot_id_snapshot: snapshot_id
             )
  end

  test "recovery cleanup rejects namespace drift while acquiring its workspace lock", ctx do
    assert {:ok, queued} = queued_replacement(ctx)
    assert {:snooze, _seconds} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)
    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    snapshot_before = Repo.get!(ProjectSnapshot, waiting.pre_import_snapshot_id)

    expired =
      waiting
      |> ProjectImportAttempt.expired_changeset(TimeHelpers.now(), "import_cancelled")
      |> Repo.update!()

    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})
    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage))

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      if Process.whereis(SnapshotReadSwitchStorage), do: Agent.stop(SnapshotReadSwitchStorage)
    end)

    assert {:ok, original_namespace} = Storage.namespace_fingerprint()

    SnapshotReadSwitchStorage.observe_namespace(fn
      ^original_namespace -> SnapshotReadSwitchStorage.override_namespace_fingerprint(String.duplicate("f", 64))
      _value -> :ok
    end)

    assert {:error, :pre_import_snapshot_cleanup_failed} = Replacement.cleanup_terminal_recovery_snapshot(expired)
    assert Repo.get!(ProjectSnapshot, snapshot_before.id) == snapshot_before
    assert Repo.get!(ProjectImportAttempt, expired.id).pre_import_snapshot_id == snapshot_before.id
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot_before.id)
  end

  test "an active recovery build is cancelled cooperatively and swept after it becomes terminal", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    assert {:snooze, 5} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: fn scope, project, attrs ->
                 {:ok,
                  pending_project_snapshot_fixture(project, %{
                    created_by_id: scope.user.id,
                    idempotency_key: attrs.idempotency_key
                  })}
               end
             )

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    now = TimeHelpers.now()

    building =
      waiting.pre_import_snapshot_id
      |> then(&Repo.get!(ProjectSnapshot, &1))
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "building",
        progress_phase: "copying",
        building_started_at: now,
        state_updated_at: now
      })
      |> Repo.update!()

    assert {:ok, expired} = Imports.cancel_import(ctx.scope, waiting.id)
    assert expired.status == "expired"
    assert expired.error_code == "import_cancelled"
    assert expired.pre_import_snapshot_id == building.id

    cancellation_requested = Repo.get!(ProjectSnapshot, building.id)
    assert cancellation_requested.lifecycle_state == "building"
    assert %DateTime{} = cancellation_requested.cancel_requested_at
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: building.id)

    cancelled_at = TimeHelpers.now()

    cancelled =
      cancellation_requested
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "cancelled",
        integrity_state: "unknown",
        progress_phase: "cancelled",
        cancelled_at: cancelled_at,
        state_updated_at: cancelled_at
      })
      |> Repo.update!()

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^expired.id),
      set: [updated_at: DateTime.add(cancelled_at, -600, :second)]
    )

    assert %{cleaned_count: 1, failure_count: 0, more?: false} =
             Replacement.cleanup_terminal_recovery_snapshots()

    refute Repo.get(ProjectSnapshot, cancelled.id)

    swept_attempt = Repo.get!(ProjectImportAttempt, expired.id)
    assert swept_attempt.status == "expired"
    assert swept_attempt.error_code == "import_cancelled"
    assert swept_attempt.pre_import_snapshot_id == nil

    assert %SnapshotCleanupIntent{reason: "abandoned_import", authority_kind: "system"} =
             Repo.get_by!(SnapshotCleanupIntent,
               project_snapshot_id_snapshot: cancelled.id
             )
  end

  test "snapshot cleanup failure does not replace the import cancellation outcome", ctx do
    assert {:ok, queued_attempt} = queued_replacement(ctx)
    queued = Repo.preload(queued_attempt, :user)

    snapshot =
      ready_snapshot_fixture(
        ctx,
        ctx.project,
        queued.snapshot_request_key,
        current_project_checksum(ctx.project)
      )

    assert {:ok, bound} =
             Replacement.ensure_snapshot_ready(
               queued,
               ctx.project,
               snapshot_request: fn _scope, _project, _attrs -> {:ok, snapshot} end
             )

    assert {:ok, restore} =
             Versioning.request_project_snapshot_restore(ctx.scope, ctx.project, snapshot, %{
               idempotency_key: Ecto.UUID.generate()
             })

    assert restore.status == "queued"
    assert {:ok, expired} = Imports.cancel_import(ctx.scope, bound.id)
    assert expired.status == "expired"
    assert expired.stage == "expired"
    assert expired.error_code == "import_cancelled"
    assert %DateTime{} = expired.completed_at
    assert expired.pre_import_snapshot_id == snapshot.id

    persisted = Repo.get!(ProjectImportAttempt, bound.id)
    assert persisted.status == "expired"
    assert persisted.stage == "expired"
    assert persisted.error_code == "import_cancelled"
    assert persisted.completed_at == expired.completed_at
    assert persisted.pre_import_snapshot_id == snapshot.id
    assert Repo.get!(ProjectSnapshot, snapshot.id).lifecycle_state == "ready"
    refute Repo.get_by(SnapshotCleanupIntent, project_snapshot_id_snapshot: snapshot.id)

    assert {:error, :pre_import_snapshot_cleanup_failed} =
             Replacement.cleanup_terminal_recovery_snapshot(persisted)
  end

  test "pending snapshot polling backs off from the durable binding age", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    assert {:snooze, 5} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: fn scope, project, attrs ->
                 {:ok,
                  pending_project_snapshot_fixture(project, %{
                    created_by_id: scope.user.id,
                    idempotency_key: attrs.idempotency_key
                  })}
               end
             )

    for {age_seconds, expected_snooze} <- [{10, 5}, {60, 15}, {300, 60}, {1_200, 300}] do
      bound_at = DateTime.add(TimeHelpers.now(), -age_seconds, :second)

      ProjectImportAttempt
      |> Repo.get!(queued.id)
      |> Ecto.Changeset.change(snapshot_reference_bound_at: bound_at)
      |> Repo.update!()

      assert {:snooze, ^expected_snooze} =
               Imports.perform_import(queued.id,
                 attempt: 1,
                 max_attempts: 3,
                 snapshot_request: fn _scope, _project, _attrs ->
                   flunk("a bound snapshot must be reused while polling")
                 end
               )
    end
  end

  test "a deleted bound checkpoint fails closed instead of requesting a different snapshot", ctx do
    assert {:ok, queued_attempt} = queued_replacement(ctx)
    queued = Repo.preload(queued_attempt, :user)
    checksum = current_project_checksum(ctx.project)
    snapshot = ready_snapshot_fixture(ctx, ctx.project, queued.snapshot_request_key, checksum)

    assert {:ok, bound} =
             Replacement.ensure_snapshot_ready(
               queued,
               ctx.project,
               snapshot_request: fn _scope, _project, _attrs -> {:ok, snapshot} end
             )

    assert bound.stage == "queued"
    assert is_binary(bound.snapshot_capture_digest)
    Repo.delete!(snapshot)

    reloaded = Repo.get!(ProjectImportAttempt, bound.id)
    assert reloaded.pre_import_snapshot_id == nil
    assert is_binary(reloaded.snapshot_capture_digest)

    assert {:error, :pre_import_snapshot_unavailable} =
             Replacement.ensure_snapshot_ready(
               reloaded,
               ctx.project,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("a deleted bound checkpoint must never be replaced silently")
               end
             )
  end

  test "a deleted pending checkpoint leaves a durable tombstone and fails closed", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    snapshot_request = fn scope, project, attrs ->
      {:ok,
       pending_project_snapshot_fixture(project, %{
         created_by_id: scope.user.id,
         idempotency_key: attrs.idempotency_key
       })}
    end

    assert {:snooze, 5} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: snapshot_request
             )

    waiting = Repo.get!(ProjectImportAttempt, queued.id)
    assert %DateTime{} = waiting.snapshot_reference_bound_at
    Repo.delete!(Repo.get!(ProjectSnapshot, waiting.pre_import_snapshot_id))

    tombstone = Repo.get!(ProjectImportAttempt, queued.id)
    assert tombstone.pre_import_snapshot_id == nil
    assert %DateTime{} = tombstone.snapshot_reference_bound_at
    assert tombstone.snapshot_capture_digest == nil

    assert {:error, :pre_import_snapshot_unavailable} =
             Replacement.ensure_snapshot_ready(
               Repo.preload(tombstone, :user),
               ctx.project,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("a deleted pending checkpoint must never be silently replaced")
               end
             )
  end

  test "the maintenance sweep cleans a terminal snapshot created before its reference was bound", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    snapshot =
      ready_snapshot_fixture(
        ctx,
        ctx.project,
        queued.snapshot_request_key,
        current_project_checksum(ctx.project)
      )

    failed_at = TimeHelpers.now()

    failed =
      queued
      |> ProjectImportAttempt.failed_changeset(%{
        status: "failed",
        stage: "failed",
        error_code: "pre_import_snapshot_request_failed",
        error_message: nil,
        error_report: %{},
        completed_at: failed_at
      })
      |> Repo.update!()

    assert failed.pre_import_snapshot_id == nil
    assert failed.snapshot_reference_bound_at == nil

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^failed.id),
      set: [updated_at: DateTime.add(failed_at, -600, :second)]
    )

    assert %{cleaned_count: 1, failure_count: 0, more?: false} =
             Replacement.cleanup_terminal_recovery_snapshots()

    refute Repo.get(ProjectSnapshot, snapshot.id)

    assert %SnapshotCleanupIntent{reason: "abandoned_import", authority_kind: "system"} =
             Repo.get_by!(SnapshotCleanupIntent,
               project_snapshot_id_snapshot: snapshot.id
             )
  end

  test "the import expiration batch runs the terminal recovery snapshot sweep", ctx do
    assert {:ok, queued_attempt} = queued_replacement(ctx)
    queued = Repo.preload(queued_attempt, :user)

    snapshot =
      ready_snapshot_fixture(
        ctx,
        ctx.project,
        queued.snapshot_request_key,
        current_project_checksum(ctx.project)
      )

    assert {:ok, bound} =
             Replacement.ensure_snapshot_ready(
               queued,
               ctx.project,
               snapshot_request: fn _scope, _project, _attrs -> {:ok, snapshot} end
             )

    failed_at = TimeHelpers.now()

    failed =
      bound
      |> ProjectImportAttempt.failed_changeset(%{
        status: "failed",
        stage: "failed",
        error_code: "import_failed",
        error_message: nil,
        error_report: %{},
        completed_at: failed_at
      })
      |> Repo.update!()

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^failed.id),
      set: [updated_at: DateTime.add(failed_at, -600, :second)]
    )

    assert {:ok, %{expired_count: 0, failure_count: 0, more?: false}} =
             Imports.expire_stale_imports_batch(snapshot_cleanup_batch_size: 1)

    refute Repo.get(ProjectSnapshot, snapshot.id)

    assert %SnapshotCleanupIntent{reason: "abandoned_import", authority_kind: "system"} =
             Repo.get_by!(SnapshotCleanupIntent,
               project_snapshot_id_snapshot: snapshot.id
             )
  end

  test "the maintenance sweep excludes snapshots owned by deleted projects", ctx do
    assert {:ok, queued} = queued_replacement(ctx)

    snapshot =
      ready_snapshot_fixture(
        ctx,
        ctx.project,
        queued.snapshot_request_key,
        current_project_checksum(ctx.project)
      )

    failed_at = TimeHelpers.now()

    failed =
      queued
      |> ProjectImportAttempt.failed_changeset(%{
        status: "failed",
        stage: "failed",
        error_code: "pre_import_snapshot_request_failed",
        error_message: nil,
        error_report: %{},
        completed_at: failed_at
      })
      |> Repo.update!()

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^failed.id),
      set: [updated_at: DateTime.add(failed_at, -600, :second)]
    )

    ctx.project
    |> Ecto.Changeset.change(deleted_at: failed_at)
    |> Repo.update!()

    assert %{cleaned_count: 0, failure_count: 0, more?: false} =
             Replacement.cleanup_terminal_recovery_snapshots()

    assert Repo.get!(ProjectSnapshot, snapshot.id)
  end

  test "a ready checkpoint replaces active narrative state and preserves recoverable state", ctx do
    preserved_settings = %{
      "import_contract" => "preserve",
      "theme" => %{"accent" => "#abcdef", "primary" => "#123456"}
    }

    assert {:ok, _configured_project} =
             Projects.update_project(ctx.scope, ctx.project.id, %{settings: preserved_settings})

    member = user_fixture()
    membership = membership_fixture(ctx.project, member, "editor")
    old_sheet = sheet_fixture(ctx.project, %{name: "Old character"})
    old_flow = flow_fixture(ctx.project, %{name: "Old flow", is_main: true})
    old_scene = scene_fixture(ctx.project, %{name: "Old scene"})

    old_sheet_with_blocks = Repo.preload(old_sheet, :blocks, force: true)

    assert {:ok, version} =
             Sheets.create_version(old_sheet_with_blocks, ctx.user.id, title: "Before Yarn replacement")

    preserved_asset =
      asset_fixture(ctx.project, ctx.user, %{blob_hash: String.duplicate("e", 64)})

    already_trashed = sheet_fixture(ctx.project, %{name: "Already trashed"})
    assert {:ok, %{entity: trashed}} = Sheets.delete_sheet_subtree(already_trashed)

    language = language_fixture(ctx.project)

    text =
      localized_text_fixture(ctx.project.id, %{
        source_type: "flow_node",
        source_id: System.unique_integer([:positive]),
        locale_code: language.locale_code
      })

    assert {:ok, glossary} =
             Localization.create_glossary_entry(ctx.project, %{
               source_term: "Gate",
               source_locale: "en",
               target_term: "Puerta",
               target_locale: language.locale_code
             })

    assert {:ok, queued} = queued_replacement(ctx)
    snapshot_request = ready_snapshot_request(ctx, current_project_checksum(ctx.project))

    assert {:ok, completed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: snapshot_request
             )

    assert completed.status == "completed"
    assert completed.import_mode == "replace_project"
    assert %DateTime{} = completed.replacement_prepared_at
    assert is_integer(completed.pre_import_snapshot_id)
    assert Repo.get!(ProjectSnapshot, completed.pre_import_snapshot_id).lifecycle_state == "ready"

    assert Repo.get!(Sheet, old_sheet.id).deleted_at
    assert Repo.get!(Flow, old_flow.id).deleted_at
    assert Repo.get!(Scene, old_scene.id).deleted_at
    assert Repo.get!(Sheet, trashed.id).deleted_at
    assert Repo.get!(Asset, preserved_asset.id).deleted_at == nil
    assert Repo.get!(ProjectLanguage, language.id).archived_at
    assert Repo.get!(LocalizedText, text.id).archived_at

    preserved_glossary = Repo.get!(GlossaryEntry, glossary.id)
    assert preserved_glossary.source_term == glossary.source_term
    assert preserved_glossary.target_term == glossary.target_term

    assert Repo.get!(Project, ctx.project.id).settings == preserved_settings
    assert Repo.get!(ProjectMembership, membership.id).role == "editor"
    assert Repo.get!(EntityVersion, version.id).storage_key == version.storage_key

    active_flows = Storyarn.Flows.list_flows(ctx.project.id)
    assert Enum.any?(active_flows, &(&1.name == "Start"))
    assert [%{name: "Start"}] = Enum.filter(active_flows, & &1.is_main)
    refute Enum.any?(active_flows, &(&1.id == old_flow.id))

    snapshot_count = Repo.aggregate(ProjectSnapshot, :count)
    active_flow_ids = active_flows |> Enum.map(& &1.id) |> Enum.sort()

    assert {:ok, replayed} =
             Imports.perform_import(completed.id,
               attempt: 2,
               max_attempts: 3,
               snapshot_request: fn _scope, _project, _attrs ->
                 flunk("a completed replacement must not request another snapshot")
               end,
               before_materialization_transaction: fn ->
                 flunk("a completed replacement must not materialize twice")
               end
             )

    assert replayed.id == completed.id
    assert replayed.pre_import_snapshot_id == completed.pre_import_snapshot_id
    assert Repo.aggregate(ProjectSnapshot, :count) == snapshot_count

    assert {:ok, :not_terminal} =
             Replacement.cleanup_terminal_recovery_snapshot(replayed)

    assert Repo.get!(ProjectSnapshot, completed.pre_import_snapshot_id).lifecycle_state == "ready"

    assert ctx.project.id
           |> Storyarn.Flows.list_flows()
           |> Enum.map(& &1.id)
           |> Enum.sort() == active_flow_ids
  end

  test "a replacement without an exact Start node leaves the project without a main flow", ctx do
    old_main = flow_fixture(ctx.project, %{name: "Old Main", is_main: true})
    filename = "replacement-without-start.zip"

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               filename,
               replaceable_yarn_archive("without-start", "Arrival")
             )

    assert {:ok, ready} = Imports.update_import_mode(ctx.scope, ready.id, "replace_project")

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    assert {:ok, completed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: ready_snapshot_request(ctx, current_project_checksum(ctx.project))
             )

    assert completed.status == "completed"
    assert Repo.get!(Flow, old_main.id).deleted_at
    assert Enum.any?(Storyarn.Flows.list_flows(ctx.project.id), &(&1.name == "Arrival"))
    refute Enum.any?(Storyarn.Flows.list_flows(ctx.project.id), & &1.is_main)
  end

  test "drift and a post-trash failure both leave the prior project active", ctx do
    old_sheet = sheet_fixture(ctx.project, %{name: "Prior project"})
    assert {:ok, queued} = queued_replacement(ctx)
    checkpoint_checksum = current_project_checksum(ctx.project)
    parent = self()

    drifting_request = fn _scope, project, attrs ->
      snapshot = ready_snapshot_fixture(ctx, project, attrs.idempotency_key, checkpoint_checksum)
      send(parent, {:drift_snapshot, snapshot.id})
      assert {:ok, _updated} = Sheets.update_sheet(old_sheet, %{name: "Concurrent edit"})
      {:ok, snapshot}
    end

    assert {:ok, failed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: drifting_request
             )

    assert failed.status == "failed"
    assert failed.error_code == "project_changed_since_import_snapshot"
    assert failed.pre_import_snapshot_id == nil
    assert_receive {:drift_snapshot, drift_snapshot_id}
    refute Repo.get(ProjectSnapshot, drift_snapshot_id)

    assert %SnapshotCleanupIntent{
             reason: "abandoned_import",
             authority_kind: "system",
             authority_actor_id: nil
           } =
             Repo.get_by!(SnapshotCleanupIntent,
               project_snapshot_id_snapshot: drift_snapshot_id
             )

    assert Repo.get!(Sheet, old_sheet.id).deleted_at == nil
    refute Enum.any?(Storyarn.Flows.list_flows(ctx.project.id), &(&1.name == "Start"))

    # A fresh attempt proves failures after the trash step also roll back the
    # old graph, the newly imported graph and the terminal transition together.
    assert {:ok, queued_again} = queued_replacement(ctx, "second-replaceable.zip")

    assert {:error, :retryable_import_error} =
             Imports.perform_import(queued_again.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: ready_snapshot_request(ctx, current_project_checksum(ctx.project)),
               before_attempt_completion: fn -> raise "injected completion failure" end
             )

    retrying = Repo.get!(ProjectImportAttempt, queued_again.id)
    assert retrying.status == "retrying"
    assert retrying.replacement_prepared_at == nil
    assert Repo.get!(Sheet, old_sheet.id).deleted_at == nil
    refute Enum.any?(Storyarn.Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
  end

  defp ready_replacement(ctx, filename \\ "replaceable-yarn.zip") do
    with {:ok, ready, _preview} <-
           Imports.prepare_import(ctx.scope, ctx.project, filename, replaceable_yarn_archive(filename)),
         true <- ready.replace_eligible do
      Imports.update_import_mode(ctx.scope, ready.id, "replace_project")
    end
  end

  defp queued_replacement(ctx, filename \\ "replaceable-yarn.zip") do
    with {:ok, ready} <- ready_replacement(ctx, filename) do
      Imports.enqueue_import(ctx.scope, ready.id, :rename,
        import_mode: "replace_project",
        replace_acknowledged: true
      )
    end
  end

  defp ready_snapshot_request(ctx, checksum) do
    fn _scope, project, attrs ->
      {:ok, ready_snapshot_fixture(ctx, project, attrs.idempotency_key, checksum)}
    end
  end

  defp ready_snapshot_fixture(ctx, project, idempotency_key, checksum) do
    full_project_snapshot_fixture(project, %{
      created_by_id: ctx.user.id,
      idempotency_key: idempotency_key,
      project_checksum: checksum,
      asset_blob_size_bytes: 0
    })
  end

  defp current_project_checksum(project) do
    assert {:ok, checksum} =
             Repo.transact(fn ->
               assets = Assets.list_assets_for_export(project.id)
               {asset_blob_hashes, asset_metadata} = AssetHashResolver.capture_catalog_maps(assets)

               snapshot =
                 project.id
                 |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(
                   localization_scope: :active,
                   include_referenced_tombstones: true
                 )
                 |> Map.put(
                   "asset_restore_contract_version",
                   AssetHashResolver.exact_restore_contract_version()
                 )
                 |> Map.put("asset_blob_hashes", asset_blob_hashes)
                 |> Map.put("asset_metadata", asset_metadata)

               SnapshotArchiveStorage.canonical_project_checksum(snapshot, assets)
             end)

    checksum
  end

  defp replaceable_yarn_archive(seed \\ "default", title \\ "Start") do
    project =
      Jason.encode!(%{
        "projectFileVersion" => 3,
        "sourceFiles" => ["*.yarn"],
        "excludeFiles" => []
      })

    entries = [
      {~c"project.yarnproject", project},
      {~c"main.yarn", "title: #{title}\n---\nA new beginning for #{seed}.\n===\n"}
    ]

    {:ok, {_name, binary}} = :zip.create(~c"replaceable-yarn.zip", entries, [:memory])
    binary
  end

  defp yarn_project_fixture_archive do
    entries =
      Enum.map(@yarn_project_fixture_files, fn relative_path ->
        source_path = Path.join(@yarn_project_fixture_root, relative_path)
        {String.to_charlist(relative_path), File.read!(source_path)}
      end)

    {:ok, {_name, binary}} = :zip.create(~c"emberfall.zip", entries, [:memory])
    binary
  end
end
