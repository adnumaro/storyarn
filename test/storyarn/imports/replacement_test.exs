defmodule Storyarn.Imports.ReplacementTest do
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
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Imports
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Replacement
  alias Storyarn.Localization
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotArchiveStorage

  setup do
    previous_restore_policy = Application.get_env(:storyarn, RestorePolicy)
    previous_import_policy = Application.get_env(:storyarn, Imports)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      Keyword.put(previous_restore_policy || [], :project_snapshot_restore, true)
    )

    Application.put_env(
      :storyarn,
      Imports,
      Keyword.put(previous_import_policy || [], :replace_project_enabled, true)
    )

    on_exit(fn ->
      restore_application_env(RestorePolicy, previous_restore_policy)
      restore_application_env(Imports, previous_import_policy)
    end)

    user = user_fixture()
    project = project_fixture(user)

    %{scope: Scope.for_user(user), user: user, project: project}
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

  test "the producer gate rejects replacement races but never strands an accepted job", ctx do
    assert {:ok, additive_ready, _preview} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               "gated-replacement.zip",
               replaceable_yarn_archive()
             )

    assert additive_ready.replace_eligible

    set_replace_producer_enabled(false)
    refute Imports.replace_project_available?()

    assert {:error, :project_snapshot_restore_disabled} =
             Imports.update_import_mode(ctx.scope, additive_ready.id, "replace_project")

    set_replace_producer_enabled(true)
    assert {:ok, ready} = Imports.update_import_mode(ctx.scope, additive_ready.id, "replace_project")

    set_replace_producer_enabled(false)

    assert {:error, :project_snapshot_restore_disabled} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"

    set_replace_producer_enabled(true)

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               import_mode: "replace_project",
               replace_acknowledged: true
             )

    # This is a producer rollout gate, not a worker kill switch. Once accepted,
    # the restore policy is the only execution-time emergency stop.
    set_replace_producer_enabled(false)

    assert {:ok, completed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               snapshot_request: ready_snapshot_request(ctx, current_project_checksum(ctx.project))
             )

    assert completed.status == "completed"
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

  test "a ready checkpoint replaces active narrative state and preserves recoverable state", ctx do
    old_sheet = sheet_fixture(ctx.project, %{name: "Old character"})
    old_flow = flow_fixture(ctx.project, %{name: "Old flow"})
    old_scene = scene_fixture(ctx.project, %{name: "Old scene"})

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
    assert is_integer(completed.pre_import_snapshot_id)
    assert Repo.get!(ProjectSnapshot, completed.pre_import_snapshot_id).lifecycle_state == "ready"

    assert Repo.get!(Sheet, old_sheet.id).deleted_at
    assert Repo.get!(Flow, old_flow.id).deleted_at
    assert Repo.get!(Scene, old_scene.id).deleted_at
    assert Repo.get!(Sheet, trashed.id).deleted_at
    assert Repo.get!(Asset, preserved_asset.id).deleted_at == nil
    assert Repo.get!(ProjectLanguage, language.id).archived_at
    assert Repo.get!(LocalizedText, text.id).archived_at
    assert Repo.get(GlossaryEntry, glossary.id) == nil

    active_flows = Storyarn.Flows.list_flows(ctx.project.id)
    assert Enum.any?(active_flows, &(&1.name == "Start"))
    refute Enum.any?(active_flows, &(&1.id == old_flow.id))
  end

  test "drift and a post-trash failure both leave the prior project active", ctx do
    old_sheet = sheet_fixture(ctx.project, %{name: "Prior project"})
    assert {:ok, queued} = queued_replacement(ctx)
    checkpoint_checksum = current_project_checksum(ctx.project)

    drifting_request = fn _scope, project, attrs ->
      snapshot = ready_snapshot_fixture(ctx, project, attrs.idempotency_key, checkpoint_checksum)
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
                 |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(localization_scope: :active)
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

  defp replaceable_yarn_archive(seed \\ "default") do
    project =
      Jason.encode!(%{
        "projectFileVersion" => 3,
        "sourceFiles" => ["*.yarn"],
        "excludeFiles" => []
      })

    entries = [
      {~c"project.yarnproject", project},
      {~c"main.yarn", "title: Start\n---\nA new beginning for #{seed}.\n===\n"}
    ]

    {:ok, {_name, binary}} = :zip.create(~c"replaceable-yarn.zip", entries, [:memory])
    binary
  end

  defp set_replace_producer_enabled(enabled?) do
    current = Application.get_env(:storyarn, Imports, [])
    Application.put_env(:storyarn, Imports, Keyword.put(current, :replace_project_enabled, enabled?))
  end

  defp restore_application_env(module, nil), do: Application.delete_env(:storyarn, module)
  defp restore_application_env(module, value), do: Application.put_env(:storyarn, module, value)
end
