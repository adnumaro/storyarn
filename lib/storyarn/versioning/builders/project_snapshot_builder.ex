defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilder do
  @moduledoc """
  Builds and restores project-level snapshots.

  A project snapshot captures the full state of all sheets, flows, and scenes
  using the per-entity builders for serialization and restoration.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Localization
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotRestorePlan
  alias Storyarn.Versioning.RestorePolicy

  require Logger

  @doc """
  Builds a full project snapshot containing all non-deleted entities.

  Returns a map with format_version, entity_counts, and per-entity-type snapshots.
  """
  @spec build_snapshot(integer()) :: map()
  def build_snapshot(project_id) do
    case Repo.transaction(
           fn ->
             project = lock_active_project_for_snapshot!(project_id)
             build_consistent_snapshot(project)
           end,
           isolation: :repeatable_read,
           timeout: to_timeout(minute: 5)
         ) do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        raise "project snapshot transaction failed: #{inspect(reason)}"
    end
  end

  defp lock_active_project_for_snapshot!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project ->
        project

      %Project{} ->
        raise ArgumentError,
              "cannot snapshot inactive project #{project_id}"

      nil ->
        raise Ecto.NoResultsError, queryable: Project
    end
  end

  defp build_consistent_snapshot(project) do
    project_id = project.id
    sheets = Sheets.list_sheets_for_export(project_id)
    flows = Flows.list_flows_for_export(project_id)
    scenes = Scenes.list_scenes_for_export(project_id)

    languages = Localization.list_languages_for_backup(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes == [],
        do: [],
        else: Localization.list_texts_for_backup(project_id, locale_codes)

    glossary = Localization.list_glossary_for_export(project_id)
    {asset_blob_hashes, asset_metadata} = localization_asset_metadata(project_id, texts)

    entity_counts = %{
      "sheets" => length(sheets),
      "flows" => length(flows),
      "scenes" => length(scenes),
      "languages" => length(languages),
      "localized_texts" => length(texts),
      "glossary_entries" => length(glossary)
    }

    %{
      "format_version" => 2,
      "project" => project_to_snapshot(project),
      "entity_counts" => entity_counts,
      "asset_blob_hashes" => asset_blob_hashes,
      "asset_metadata" => asset_metadata,
      "sheets" =>
        Enum.map(sheets, fn sheet ->
          %{"id" => sheet.id, "snapshot" => SheetBuilder.build_snapshot(sheet)}
        end),
      "flows" =>
        Enum.map(flows, fn flow ->
          %{"id" => flow.id, "snapshot" => FlowBuilder.build_snapshot(flow)}
        end),
      "scenes" =>
        Enum.map(scenes, fn scene ->
          %{"id" => scene.id, "snapshot" => SceneBuilder.build_snapshot(scene)}
        end),
      "tree" => %{
        "sheets" =>
          Enum.map(
            sheets,
            &%{"id" => &1.id, "parent_id" => &1.parent_id, "position" => &1.position}
          ),
        "flows" =>
          Enum.map(
            flows,
            &%{"id" => &1.id, "parent_id" => &1.parent_id, "position" => &1.position}
          ),
        "scenes" =>
          Enum.map(
            scenes,
            &%{"id" => &1.id, "parent_id" => &1.parent_id, "position" => &1.position}
          )
      },
      "localization" => %{
        "languages" => Enum.map(languages, &language_to_snapshot/1),
        "texts" => Enum.map(texts, &text_to_snapshot/1),
        "glossary" => Enum.map(glossary, &glossary_entry_to_snapshot/1)
      }
    }
  end

  defp localization_asset_metadata(project_id, texts) do
    texts
    |> Enum.map(& &1.vo_asset_id)
    |> AssetHashResolver.resolve_hashes_for_project!(project_id)
  end

  defp project_to_snapshot(project) do
    %{
      "description" => project.description,
      "project_type" => project.project_type,
      "project_subtype" => project.project_subtype,
      "project_type_other" => project.project_type_other,
      "settings" => project.settings,
      "auto_snapshots_enabled" => project.auto_snapshots_enabled,
      "auto_version_flows" => project.auto_version_flows,
      "auto_version_scenes" => project.auto_version_scenes,
      "auto_version_sheets" => project.auto_version_sheets
    }
  end

  @doc """
  Restores all entities in a project from a snapshot.

  Reconciles the active project to the exact snapshot graph. Snapshot roots
  and supported children are restored with their original IDs, including rows
  that currently exist in trash. Hard-deleted roots are recreated. Active
  roots absent from the snapshot are moved to trash, while unrelated
  pre-existing trash remains untouched.

  Wrapped in a transaction for atomicity.

  ## Options
  - `:user_id` - User performing the restore (for audit trail)
  - `:asset_copy_tracker` - External storage compensation tracker. When
    supplied, its caller owns finalization after the surrounding transaction.
  """
  @spec restore_snapshot(integer(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def restore_snapshot(project_id, snapshot, opts \\ []) do
    snapshot = FlowSnapshotNormalizer.normalize_project(snapshot)

    with :ok <- RestorePolicy.ensure_enabled(:project_snapshot_restore),
         {:ok, tracker, owns_tracker?} <- asset_copy_tracker(opts) do
      run_restore_scope(
        project_id,
        snapshot,
        Keyword.put(opts, :asset_copy_tracker, tracker),
        tracker,
        owns_tracker?
      )
    end
  end

  defp run_restore_scope(project_id, snapshot, opts, tracker, owns_tracker?) do
    AssetMaterializationScope.run(opts, fn scoped_opts ->
      restore_with_tracker(
        project_id,
        snapshot,
        scoped_opts,
        tracker,
        owns_tracker?
      )
    end)
  end

  defp restore_with_tracker(project_id, snapshot, opts, tracker, owns_tracker?) do
    result =
      Repo.transaction(
        fn ->
          project = lock_active_project_for_restore!(project_id)
          :ok = lock_pre_restore_snapshot_record!(project_id, opts)
          current_snapshot = current_restore_baseline!(project, opts)
          plan = build_restore_plan!(snapshot)
          root_result = prepare_restore_roots!(project_id, plan)
          :ok = apply_restore_tree!(project_id, plan)
          _project = restore_project_metadata!(project, plan)

          results = restore_project_entities(project_id, plan, opts)

          restore_localization(
            project_id,
            snapshot,
            current_snapshot,
            collect_localization_id_maps(results),
            opts
          )

          :ok = verify_restored_project!(project_id, plan)

          case prepare_asset_cleanup_handoff(tracker, owns_tracker?) do
            :ok ->
              %{
                restored: count_restored(results),
                skipped: count_skipped(results),
                removed: root_result.removed,
                details: results
              }

            {:error, reason} ->
              Repo.rollback({:storage_cleanup_handoff_failed, reason})
          end
        end,
        timeout: to_timeout(minute: 5)
      )

    finalize_asset_copies(result, tracker, owns_tracker?)
  rescue
    error in AssetCopyError ->
      asset_copy_error_result(error, cleanup_owned_asset_copies(tracker, owns_tracker?))

    error ->
      tracker
      |> cleanup_owned_asset_copies(owns_tracker?)
      |> log_asset_cleanup_failure()

      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      tracker
      |> cleanup_owned_asset_copies(owns_tracker?)
      |> log_asset_cleanup_failure()

      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp restore_project_entities(project_id, plan, opts) do
    sheets =
      restore_entities(
        project_id,
        "sheets",
        plan.ordered.sheets,
        &restore_sheet(&1, &2, project_id, opts)
      )

    flows =
      restore_entities(
        project_id,
        "flows",
        plan.ordered.flows,
        &restore_flow(&1, &2, project_id, opts)
      )

    reconcile_project_flow_trash_refs!(project_id, plan)

    scenes =
      restore_entities(
        project_id,
        "scenes",
        plan.ordered.scenes,
        &restore_scene(&1, &2, project_id, opts)
      )

    %{
      sheets: sheets,
      flows: flows,
      scenes: scenes
    }
  end

  defp reconcile_project_flow_trash_refs!(project_id, plan) do
    target_flow_ids = plan.ids.flows |> MapSet.to_list() |> Enum.sort()

    target_snapshot_node_ids =
      plan.entries.flows
      |> Enum.flat_map(fn entry ->
        entry
        |> get_in(["snapshot", "nodes"])
        |> List.wrap()
        |> Enum.flat_map(fn
          %{"original_id" => id} when is_integer(id) and id > 0 -> [id]
          _invalid -> []
        end)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    case Flows.reconcile_project_restore_flow_refs(
           project_id,
           target_flow_ids,
           target_snapshot_node_ids
         ) do
      {:ok, _counts} ->
        :ok

      {:error, reason} ->
        Repo.rollback({:project_snapshot_flow_trash_reference_reconciliation_failed, reason})
    end
  end

  defp asset_copy_tracker(opts) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        {:ok, reference, false}

      _reference ->
        if Repo.in_transaction?(),
          do: {:error, :asset_copy_tracker_required_in_transaction},
          else: {:ok, StorageCompensation.new(), true}
    end
  end

  defp finalize_asset_copies({:ok, _result} = result, tracker, true) do
    StorageCompensation.discard(tracker)
    result
  end

  defp finalize_asset_copies({:error, _reason} = result, tracker, true) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        result

      {:error, cleanup_reason} ->
        {:error, {:asset_storage_cleanup_failed, result, cleanup_reason}}
    end
  end

  defp finalize_asset_copies(result, _tracker, false), do: result

  defp prepare_asset_cleanup_handoff(tracker, true), do: StorageCompensation.prepare_unretained_cleanup(tracker)

  defp prepare_asset_cleanup_handoff(_tracker, false), do: :ok

  defp asset_copy_error_result(%AssetCopyError{} = error, :ok) do
    {:error, {:asset_materialization_failed, error.asset_id, error.reason}}
  end

  defp asset_copy_error_result(%AssetCopyError{} = error, {:error, cleanup_reason}) do
    {:error,
     {:asset_storage_cleanup_failed, {:asset_materialization_failed, error.asset_id, error.reason}, cleanup_reason}}
  end

  defp cleanup_owned_asset_copies(tracker, true), do: StorageCompensation.cleanup_after_rollback(tracker)

  defp cleanup_owned_asset_copies(_tracker, false), do: :ok

  defp log_asset_cleanup_failure(:ok), do: :ok

  defp log_asset_cleanup_failure({:error, cleanup_reason}) do
    Logger.error(
      "Could not compensate project snapshot asset copies after an exception: " <>
        inspect(cleanup_reason)
    )
  end

  defp lock_active_project_for_restore!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, project} -> project
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp restore_entities(project_id, entity_key, entity_snapshots, restore_fn) do
    Enum.map(entity_snapshots, fn entry ->
      entity_id = entry["id"]

      case restore_fn.(entity_id, entry["snapshot"]) do
        {:ok, _entity, id_maps} ->
          {:restored, entity_id, id_maps}

        {:ok, _entity} ->
          {:restored, entity_id}

        {:error, reason} ->
          Logger.warning("Failed to restore #{entity_key} #{entity_id} in project #{project_id}: #{inspect(reason)}")

          Repo.rollback({:restore_failed, entity_key, entity_id, reason})
      end
    end)
  end

  defp restore_sheet(sheet_id, snapshot, project_id, opts) do
    case Sheets.get_sheet(project_id, sheet_id) do
      nil ->
        {:error, :not_found}

      sheet ->
        SheetBuilder.restore_snapshot(
          sheet,
          snapshot,
          opts
          |> Keyword.put(:return_id_maps, true)
          |> Keyword.put(:full_project_restore, true)
          |> Keyword.put(:restore_action, :project_snapshot_restore)
        )
    end
  end

  defp restore_flow(flow_id, snapshot, project_id, opts) do
    case Flows.get_flow(project_id, flow_id) do
      nil ->
        {:error, :not_found}

      flow ->
        FlowBuilder.restore_snapshot(
          flow,
          snapshot,
          opts
          |> Keyword.put(:return_id_maps, true)
          |> Keyword.put(:full_project_restore, true)
          |> Keyword.put(:restore_action, :project_snapshot_restore)
        )
    end
  end

  defp restore_scene(scene_id, snapshot, project_id, opts) do
    case Scenes.get_scene(project_id, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        SceneBuilder.restore_snapshot(
          scene,
          snapshot,
          Keyword.put(opts, :restore_action, :project_snapshot_restore)
        )
    end
  end

  defp count_restored(results) do
    Enum.sum(
      for {_key, entries} <- results do
        Enum.count(entries, &(elem(&1, 0) == :restored))
      end
    )
  end

  defp count_skipped(results) do
    Enum.sum(
      for {_key, entries} <- results do
        Enum.count(entries, &(elem(&1, 0) == :skipped))
      end
    )
  end

  defp current_restore_baseline!(project, opts) do
    current_snapshot = build_consistent_snapshot(project)

    case Keyword.fetch(opts, :pre_restore_snapshot) do
      {:ok, pre_restore_snapshot} when is_map(pre_restore_snapshot) ->
        if canonical_project_snapshot(current_snapshot) ==
             canonical_project_snapshot(pre_restore_snapshot) do
          current_snapshot
        else
          Repo.rollback(:project_changed_since_pre_restore_snapshot)
        end

      {:ok, _invalid} ->
        Repo.rollback(:invalid_pre_restore_snapshot)

      :error ->
        # The product restore boundary always supplies a verified safety
        # snapshot. Keeping this optional here allows isolated builder tests and
        # trusted internal migrations to exercise the transactional materializer.
        current_snapshot
    end
  end

  defp lock_pre_restore_snapshot_record!(project_id, opts) do
    case Keyword.fetch(opts, :pre_restore_snapshot_identity) do
      {:ok, identity} ->
        lock_and_verify_pre_restore_snapshot_record!(
          project_id,
          Keyword.get(opts, :user_id),
          identity
        )

      :error ->
        # Product restores always supply this identity. It remains optional at
        # this internal builder boundary for isolated materializer tests and
        # trusted internal migrations.
        :ok
    end
  end

  defp lock_and_verify_pre_restore_snapshot_record!(project_id, user_id, identity) do
    if !valid_pre_restore_snapshot_identity?(project_id, user_id, identity) do
      Repo.rollback(:invalid_pre_restore_snapshot_identity)
    end

    snapshot_id = identity.id

    snapshot =
      Repo.one(
        from(candidate in ProjectSnapshot,
          where:
            candidate.id == ^snapshot_id and
              candidate.project_id == ^project_id,
          lock: "FOR SHARE"
        )
      )

    case snapshot do
      %ProjectSnapshot{} ->
        if pre_restore_snapshot_identity(snapshot) == identity do
          :ok
        else
          Repo.rollback(:pre_restore_snapshot_identity_mismatch)
        end

      nil ->
        Repo.rollback(:pre_restore_snapshot_not_durable)
    end
  end

  defp valid_pre_restore_snapshot_identity?(project_id, user_id, %{
         id: snapshot_id,
         project_id: identity_project_id,
         created_by_id: identity_user_id,
         version_number: version_number,
         storage_key: storage_key,
         snapshot_size_bytes: snapshot_size_bytes,
         checksum: checksum,
         entity_counts: entity_counts
       }) do
    values_valid? =
      Enum.all?(
        [
          {snapshot_id, &positive_integer_value?/1},
          {project_id, &positive_integer_value?/1},
          {user_id, &positive_integer_value?/1},
          {version_number, &positive_integer_value?/1},
          {storage_key, &is_binary/1},
          {snapshot_size_bytes, &nonnegative_integer_value?/1},
          {checksum, &is_binary/1},
          {entity_counts, &is_map/1}
        ],
        fn {value, validator} -> validator.(value) end
      )

    values_valid? and identity_project_id == project_id and
      identity_user_id == user_id
  end

  defp valid_pre_restore_snapshot_identity?(_project_id, _user_id, _identity), do: false

  defp positive_integer_value?(value), do: is_integer(value) and value > 0

  defp nonnegative_integer_value?(value), do: is_integer(value) and value >= 0

  defp pre_restore_snapshot_identity(%ProjectSnapshot{} = snapshot) do
    %{
      id: snapshot.id,
      project_id: snapshot.project_id,
      created_by_id: snapshot.created_by_id,
      version_number: snapshot.version_number,
      storage_key: snapshot.storage_key,
      snapshot_size_bytes: snapshot.snapshot_size_bytes,
      checksum: snapshot.checksum,
      entity_counts: snapshot.entity_counts
    }
  end

  defp canonical_project_snapshot(snapshot) do
    snapshot
    |> Jason.encode!()
    |> Jason.decode!()
    |> FlowSnapshotNormalizer.normalize_project()
  end

  defp build_restore_plan!(snapshot) do
    case ProjectSnapshotRestorePlan.build(snapshot) do
      {:ok, plan} -> plan
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp prepare_restore_roots!(project_id, plan) do
    case ProjectSnapshotRestorePlan.prepare(project_id, plan) do
      {:ok, result} -> result
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp apply_restore_tree!(project_id, plan) do
    case ProjectSnapshotRestorePlan.apply_tree(project_id, plan) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp restore_project_metadata!(project, plan) do
    case ProjectSnapshotRestorePlan.restore_project_metadata(project, plan) do
      {:ok, restored_project} -> restored_project
      {:error, reason} -> Repo.rollback({:project_metadata_restore_failed, reason})
    end
  end

  defp verify_restored_project!(project_id, plan) do
    with :ok <- verify_main_flow!(project_id, plan.entries.flows),
         :ok <- verify_sheet_inheritance!(plan.ordered.sheets),
         :ok <- verify_flow_references(plan.ordered.flows),
         :ok <- References.rebuild_project_entity_references(project_id) do
      References.rebuild_project_variable_references(project_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp verify_main_flow!(project_id, flow_entries) do
    expected_ids =
      flow_entries
      |> Enum.filter(&(&1["snapshot"]["is_main"] == true))
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    actual_ids =
      Repo.all(
        from(flow in Flow,
          where: flow.project_id == ^project_id and flow.is_main == true and is_nil(flow.deleted_at),
          order_by: [asc: flow.id],
          select: flow.id
        )
      )

    if actual_ids == expected_ids do
      :ok
    else
      {:error, {:project_snapshot_main_flow_mismatch, expected_ids, actual_ids}}
    end
  end

  defp verify_sheet_inheritance!(entries) do
    Enum.each(entries, fn entry ->
      Sheet
      |> Repo.get!(entry["id"])
      |> PropertyInheritance.verify_restored_sheet_inheritance!()
    end)

    :ok
  end

  defp verify_flow_references(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case FlowBuilder.validate_materialized_reference_cycles(entry["id"]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp collect_localization_id_maps(results) do
    results
    |> Map.values()
    |> List.flatten()
    |> Enum.reduce(%{sheet: %{}, block: %{}, node: %{}}, fn
      {:restored, _entity_id, id_maps}, acc ->
        Map.merge(acc, Map.take(id_maps, [:sheet, :block, :node]), fn _key, left, right ->
          Map.merge(left, right)
        end)

      _result, acc ->
        acc
    end)
  end

  # ========== Localization Snapshots ==========

  defp language_to_snapshot(language) do
    %{
      "locale_code" => language.locale_code,
      "name" => language.name,
      "is_source" => language.is_source,
      "position" => language.position,
      "archived_at" => language.archived_at
    }
  end

  defp text_to_snapshot(text) do
    %{
      "source_type" => text.source_type,
      "source_id" => text.source_id,
      "source_field" => text.source_field,
      "source_text" => text.source_text,
      "source_text_hash" => text.source_text_hash,
      "translated_source_hash" => text.translated_source_hash,
      "locale_code" => text.locale_code,
      "translated_text" => text.translated_text,
      "status" => text.status,
      "vo_status" => text.vo_status,
      "vo_asset_id" => text.vo_asset_id,
      "translator_notes" => text.translator_notes,
      "reviewer_notes" => text.reviewer_notes,
      "speaker_sheet_id" => text.speaker_sheet_id,
      "word_count" => text.word_count,
      "content_role" => text.content_role,
      "vo_eligible" => text.vo_eligible,
      "machine_translated" => text.machine_translated,
      "last_translated_at" => text.last_translated_at,
      "last_reviewed_at" => text.last_reviewed_at,
      "translated_by_id" => text.translated_by_id,
      "reviewed_by_id" => text.reviewed_by_id,
      "archived_at" => text.archived_at,
      "archive_reason" => text.archive_reason
    }
  end

  defp glossary_entry_to_snapshot(entry) do
    %{
      "source_term" => entry.source_term,
      "source_locale" => entry.source_locale,
      "target_term" => entry.target_term,
      "target_locale" => entry.target_locale,
      "context" => entry.context,
      "do_not_translate" => entry.do_not_translate
    }
  end

  # ========== Localization Restore ==========

  defp restore_localization(_project_id, %{"localization" => nil}, _current_snapshot, _id_maps, _opts), do: :ok

  defp restore_localization(_project_id, snapshot, _current_snapshot, _id_maps, _opts)
       when not is_map_key(snapshot, "localization"), do: :ok

  defp restore_localization(project_id, snapshot, current_snapshot, id_maps, opts) do
    localization = snapshot["localization"]
    now = TimeHelpers.now()

    # Replace rows for target sources, archive rows whose sources are moving
    # from the active graph to trash, and leave pre-existing trash untouched.
    reconcile_localization_restore_scope(project_id, snapshot, current_snapshot, now)
    Repo.delete_all(from(g in GlossaryEntry, where: g.project_id == ^project_id))
    Repo.delete_all(from(l in ProjectLanguage, where: l.project_id == ^project_id))
    restore_languages(project_id, Map.get(localization, "languages", []), now)

    texts =
      localization
      |> Map.get("texts", [])
      |> materializable_localization_texts!(snapshot)

    restore_texts(project_id, texts, id_maps, snapshot, opts, now)
    restore_glossary(project_id, Map.get(localization, "glossary", []), now)
  end

  defp reconcile_localization_restore_scope(project_id, target_snapshot, current_snapshot, now) do
    target_ids = localization_source_ids(target_snapshot)
    current_ids = localization_source_ids(current_snapshot)

    Enum.each(~w(sheet block flow_node), fn source_type ->
      target_source_ids = target_ids |> Map.fetch!(source_type) |> MapSet.to_list()

      if target_source_ids != [] do
        Repo.delete_all(
          from(text in LocalizedText,
            where:
              text.project_id == ^project_id and
                text.source_type == ^source_type and
                text.source_id in ^target_source_ids
          )
        )
      end

      current_only_source_ids =
        current_ids
        |> Map.fetch!(source_type)
        |> MapSet.difference(Map.fetch!(target_ids, source_type))
        |> MapSet.to_list()

      if current_only_source_ids != [] do
        Repo.update_all(
          from(text in LocalizedText,
            where:
              text.project_id == ^project_id and
                text.source_type == ^source_type and
                text.source_id in ^current_only_source_ids and
                is_nil(text.archived_at)
          ),
          set: [
            archived_at: now,
            archive_reason: "source_deleted",
            updated_at: now
          ],
          inc: [lock_version: 1]
        )
      end
    end)
  end

  defp localization_source_ids(snapshot) do
    %{
      "sheet" =>
        snapshot
        |> Map.get("sheets", [])
        |> MapSet.new(& &1["id"]),
      "block" =>
        snapshot
        |> Map.get("sheets", [])
        |> Enum.flat_map(&get_in(&1, ["snapshot", "blocks"]))
        |> MapSet.new(& &1["original_id"]),
      "flow_node" =>
        snapshot
        |> Map.get("flows", [])
        |> Enum.flat_map(&get_in(&1, ["snapshot", "nodes"]))
        |> MapSet.new(& &1["original_id"])
    }
  end

  defp materializable_localization_texts!(texts, snapshot) when is_list(texts) do
    source_ids = localization_source_ids(snapshot)

    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, restorable} ->
      source_type = text["source_type"]
      source_id = text["source_id"]

      case Map.fetch(source_ids, source_type) do
        {:ok, ids} ->
          materializable_localization_text_result(
            text,
            source_id,
            ids,
            restorable
          )

        :error ->
          {:halt, {:error, invalid_localization_source(text)}}
      end
    end)
    |> case do
      {:ok, restorable} -> Enum.reverse(restorable)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp materializable_localization_texts!(_texts, _snapshot) do
    Repo.rollback(:invalid_project_snapshot_localization_texts)
  end

  defp materializable_localization_text_result(text, source_id, source_ids, restorable) do
    if MapSet.member?(source_ids, source_id) do
      {:cont, {:ok, [text | restorable]}}
    else
      defer_archived_localization_text(text, restorable)
    end
  end

  defp defer_archived_localization_text(text, restorable) do
    archived_at = parse_datetime(text["archived_at"])
    metadata = SourceContract.field_metadata(text["source_type"], text["source_field"])

    if is_integer(text["source_id"]) and text["source_id"] > 0 and
         match?(%DateTime{}, archived_at) and not is_nil(metadata) do
      {:cont, {:ok, restorable}}
    else
      {:halt, {:error, invalid_localization_source(text)}}
    end
  end

  defp invalid_localization_source(text) do
    {
      :invalid_project_snapshot_localization_source,
      text["source_type"],
      text["source_id"],
      text["source_field"],
      text["locale_code"]
    }
  end

  defp restore_languages(_project_id, [], _now), do: :ok

  defp restore_languages(project_id, languages, now) do
    entries =
      Enum.map(languages, fn lang ->
        %{
          project_id: project_id,
          locale_code: lang["locale_code"],
          name: lang["name"],
          is_source: lang["is_source"] || false,
          position: lang["position"] || 0,
          archived_at: parse_datetime(lang["archived_at"]),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectLanguage, entries)
  end

  defp restore_texts(_project_id, [], _id_maps, _snapshot, _opts, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, snapshot, opts, now) do
    context =
      project_id
      |> localization_restore_context(texts, id_maps, snapshot)
      |> Map.merge(%{
        project_id: project_id,
        snapshot: snapshot,
        opts: opts,
        user_id: Keyword.get(opts, :user_id)
      })

    texts
    |> Enum.map(&localization_text_restore_entry(&1, project_id, id_maps, context, now))
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
  end

  defp localization_text_restore_entry(text, project_id, id_maps, context, now) do
    metadata = SourceContract.field_metadata(text["source_type"], text["source_field"])
    source_id = remap_localization_source_id(text, id_maps)

    validate_localization_text_source!(text, metadata, source_id, context.locales)

    archived_at = parse_datetime(text["archived_at"])
    vo_asset_id = restored_vo_asset_id(text, metadata, context)
    speaker_sheet_id = restored_speaker_sheet_id(text, metadata, archived_at, id_maps, context)
    translated_source_hash = translated_source_hash(text)

    %{
      project_id: project_id,
      source_type: text["source_type"],
      source_id: source_id,
      source_field: text["source_field"],
      source_text: text["source_text"],
      source_text_hash: text["source_text_hash"],
      translated_source_hash: translated_source_hash,
      locale_code: text["locale_code"],
      translated_text: text["translated_text"],
      status: restored_status(text, translated_source_hash),
      vo_status: restored_vo_status(text["vo_status"], metadata.vo_eligible, vo_asset_id),
      vo_asset_id: if(metadata.vo_eligible, do: vo_asset_id),
      translator_notes: text["translator_notes"],
      reviewer_notes: text["reviewer_notes"],
      speaker_sheet_id: speaker_sheet_id,
      word_count: text["word_count"],
      content_role: metadata.content_role,
      vo_eligible: metadata.vo_eligible,
      machine_translated: text["machine_translated"] || false,
      last_translated_at: parse_datetime(text["last_translated_at"]),
      last_reviewed_at: parse_datetime(text["last_reviewed_at"]),
      translated_by_id: valid_id(text["translated_by_id"], context.users),
      reviewed_by_id: valid_id(text["reviewed_by_id"], context.users),
      archived_at: archived_at,
      archive_reason: restored_archive_reason(text["archive_reason"], archived_at),
      inserted_at: now,
      updated_at: now
    }
  end

  defp validate_localization_text_source!(text, metadata, source_id, locales) do
    if is_nil(metadata) or is_nil(source_id) or
         not MapSet.member?(locales, text["locale_code"]) do
      Repo.rollback(
        {:invalid_project_snapshot_localization_source, text["source_type"], text["source_id"], text["source_field"],
         text["locale_code"]}
      )
    end
  end

  defp restored_speaker_sheet_id(_text, %{content_role: content_role}, _archived_at, _id_maps, _context)
       when content_role not in ~w(dialogue response), do: nil

  defp restored_speaker_sheet_id(text, _metadata, archived_at, id_maps, context) do
    speaker_sheet_id =
      text["speaker_sheet_id"]
      |> remap_optional_id(id_maps.sheet)
      |> valid_id(context.sheets)

    if is_nil(archived_at) and not is_nil(text["speaker_sheet_id"]) and
         is_nil(speaker_sheet_id) do
      Repo.rollback(
        {:invalid_project_snapshot_localization_speaker, text["source_type"], text["source_id"], text["source_field"],
         text["speaker_sheet_id"]}
      )
    end

    speaker_sheet_id
  end

  defp localization_restore_context(project_id, texts, id_maps, snapshot) do
    speaker_ids =
      texts
      |> Enum.map(&remap_optional_id(&1["speaker_sheet_id"], id_maps.sheet))
      |> Enum.reject(&is_nil/1)

    target_sheet_ids =
      snapshot
      |> Map.get("sheets", [])
      |> Enum.map(&remap_optional_id(&1["id"], id_maps.sheet))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %{
      locales:
        from(language in ProjectLanguage, where: language.project_id == ^project_id, select: language.locale_code)
        |> Repo.all()
        |> MapSet.new(),
      assets: project_entity_ids(Asset, project_id, Enum.map(texts, & &1["vo_asset_id"])),
      sheets:
        Sheet
        |> project_entity_ids(project_id, speaker_ids)
        |> MapSet.intersection(target_sheet_ids),
      users: existing_entity_ids(User, Enum.flat_map(texts, &[&1["translated_by_id"], &1["reviewed_by_id"]]))
    }
  end

  defp project_entity_ids(schema, project_id, ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(record in schema, where: record.project_id == ^project_id and record.id in ^ids, select: record.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp existing_entity_ids(schema, ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()
    from(record in schema, where: record.id in ^ids, select: record.id) |> Repo.all() |> MapSet.new()
  end

  defp remap_optional_id(nil, _id_map), do: nil
  defp remap_optional_id(id, id_map), do: Map.get(id_map, id)

  defp valid_id(nil, _valid_ids), do: nil
  defp valid_id(id, valid_ids), do: if(MapSet.member?(valid_ids, id), do: id)

  defp restored_status(text, translated_source_hash) do
    translated? = is_binary(text["translated_text"]) and String.trim(text["translated_text"]) != ""

    current? =
      translated? and not is_nil(text["source_text_hash"]) and
        translated_source_hash == text["source_text_hash"]

    case text["status"] do
      "final" when not current? -> if(translated?, do: "review", else: "pending")
      status when status in ~w(pending draft in_progress review final) -> status
      _invalid -> if(translated?, do: "draft", else: "pending")
    end
  end

  defp restored_vo_asset_id(_text, %{vo_eligible: false}, _context), do: nil
  defp restored_vo_asset_id(%{"vo_asset_id" => nil}, %{vo_eligible: true}, _context), do: nil

  defp restored_vo_asset_id(%{"vo_asset_id" => asset_id}, %{vo_eligible: true}, context) do
    cond do
      Keyword.get(context.opts, :asset_mode) == :drop ->
        nil

      recoverable_asset_catalog_entry?(context.snapshot, asset_id) ->
        AssetHashResolver.resolve_asset_fk(
          asset_id,
          context.snapshot,
          context.project_id,
          context.user_id,
          localization_asset_opts(context.opts)
        )

      true ->
        valid_id(asset_id, context.assets)
    end
  end

  defp recoverable_asset_catalog_entry?(snapshot, asset_id) do
    id = to_string(asset_id)

    is_binary(get_in(snapshot, ["asset_blob_hashes", id])) and
      is_map(get_in(snapshot, ["asset_metadata", id]))
  end

  defp localization_asset_opts(opts) do
    Keyword.take(opts, [
      :asset_copy_tracker,
      :asset_error_mode,
      :asset_materialization_cache,
      :asset_mode,
      :asset_source_keys
    ])
  end

  defp restored_vo_status(_status, false, _asset_id), do: "none"
  defp restored_vo_status(status, true, nil) when status in ~w(recorded approved), do: "needed"
  defp restored_vo_status(status, true, _asset_id) when status in ~w(none needed recorded approved), do: status
  defp restored_vo_status(_status, true, _asset_id), do: "none"

  defp restored_archive_reason(reason, %DateTime{})
       when reason in ~w(source_deleted source_field_removed source_not_runtime version_replaced), do: reason

  defp restored_archive_reason(_reason, _archived_at), do: nil

  defp remap_localization_source_id(%{"source_type" => "flow_node", "source_id" => old_id}, id_maps),
    do: Map.get(id_maps.node, old_id)

  defp remap_localization_source_id(%{"source_type" => "block", "source_id" => old_id}, id_maps),
    do: Map.get(id_maps.block, old_id)

  defp remap_localization_source_id(%{"source_type" => "sheet", "source_id" => old_id}, id_maps),
    do: Map.get(id_maps.sheet, old_id)

  defp remap_localization_source_id(_text, _id_maps), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp translated_source_hash(%{"translated_source_hash" => hash}) when is_binary(hash), do: hash

  defp translated_source_hash(text) do
    if is_binary(text["translated_text"]) and String.trim(text["translated_text"]) != "" do
      text["source_text_hash"]
    end
  end

  defp restore_glossary(_project_id, [], _now), do: :ok

  defp restore_glossary(project_id, glossary, now) do
    glossary
    |> Enum.map(fn entry ->
      %{
        project_id: project_id,
        source_term: entry["source_term"],
        source_locale: entry["source_locale"],
        target_term: entry["target_term"],
        target_locale: entry["target_locale"],
        context: entry["context"],
        do_not_translate: entry["do_not_translate"] || false,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(GlossaryEntry, chunk) end)
  end
end
