defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilder do
  @moduledoc """
  Builds and restores project-level snapshots.

  A project snapshot captures the full state of all sheets, flows, and scenes
  using the per-entity builders for serialization and restoration.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
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
      "project_type" => project.project_type,
      "project_subtype" => project.project_subtype,
      "project_type_other" => project.project_type_other
    }
  end

  @doc """
  Restores all entities in a project from a snapshot.

  For each entity in the snapshot, finds the matching current entity by ID
  and restores it using the per-entity builder. Entities that no longer exist
  (soft-deleted or hard-deleted) are skipped. Entities not in the snapshot
  are left untouched.

  Wrapped in a transaction for atomicity.

  ## Options
  - `:user_id` - User performing the restore (for audit trail)
  """
  @spec restore_snapshot(integer(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def restore_snapshot(project_id, snapshot, opts \\ []) do
    with :ok <- RestorePolicy.ensure_enabled(:project_snapshot_restore) do
      snapshot = FlowSnapshotNormalizer.normalize_project(snapshot)

      Repo.transaction(
        fn ->
          results = %{
            sheets:
              restore_entities(
                project_id,
                snapshot,
                "sheets",
                &restore_sheet(&1, &2, project_id, opts)
              ),
            flows:
              restore_entities(
                project_id,
                snapshot,
                "flows",
                &restore_flow(&1, &2, project_id, opts)
              ),
            scenes:
              restore_entities(
                project_id,
                snapshot,
                "scenes",
                &restore_scene(&1, &2, project_id, opts)
              )
          }

          restore_localization(project_id, snapshot, collect_localization_id_maps(results))

          %{
            restored: count_restored(results),
            skipped: count_skipped(results),
            details: results
          }
        end,
        timeout: to_timeout(minute: 5)
      )
    end
  end

  defp restore_entities(project_id, snapshot, entity_key, restore_fn) do
    entity_snapshots = Map.get(snapshot, entity_key, [])

    Enum.map(entity_snapshots, fn entry ->
      entity_id = entry["id"]

      case restore_fn.(entity_id, entry["snapshot"]) do
        {:ok, _entity, id_maps} ->
          {:restored, entity_id, id_maps}

        {:ok, _entity} ->
          {:restored, entity_id}

        {:error, :not_found} ->
          {:skipped, entity_id}

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

  defp restore_localization(_project_id, %{"localization" => nil}, _id_maps), do: :ok

  defp restore_localization(_project_id, snapshot, _id_maps) when not is_map_key(snapshot, "localization"), do: :ok

  defp restore_localization(project_id, snapshot, id_maps) do
    localization = snapshot["localization"]
    now = TimeHelpers.now()

    # Delete existing localization data (order: texts first due to no FK deps)
    Repo.delete_all(from(lt in LocalizedText, where: lt.project_id == ^project_id))
    Repo.delete_all(from(g in GlossaryEntry, where: g.project_id == ^project_id))
    Repo.delete_all(from(l in ProjectLanguage, where: l.project_id == ^project_id))
    restore_languages(project_id, Map.get(localization, "languages", []), now)
    restore_texts(project_id, Map.get(localization, "texts", []), id_maps, now)
    restore_glossary(project_id, Map.get(localization, "glossary", []), now)
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

  defp restore_texts(_project_id, [], _id_maps, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, now) do
    context = localization_restore_context(project_id, texts, id_maps)

    texts
    |> Enum.flat_map(fn text ->
      metadata = SourceContract.field_metadata(text["source_type"], text["source_field"])
      source_id = remap_localization_source_id(text, id_maps)

      if is_nil(metadata) or is_nil(source_id) or not MapSet.member?(context.locales, text["locale_code"]) do
        []
      else
        vo_asset_id = valid_id(text["vo_asset_id"], context.assets)
        speaker_sheet_id = text["speaker_sheet_id"] |> remap_optional_id(id_maps.sheet) |> valid_id(context.sheets)
        translated_source_hash = translated_source_hash(text)
        archived_at = parse_datetime(text["archived_at"])

        [
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
            speaker_sheet_id: if(metadata.content_role == "dialogue", do: speaker_sheet_id),
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
        ]
      end
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
  end

  defp localization_restore_context(project_id, texts, id_maps) do
    speaker_ids =
      texts
      |> Enum.map(&remap_optional_id(&1["speaker_sheet_id"], id_maps.sheet))
      |> Enum.reject(&is_nil/1)

    %{
      locales:
        from(language in ProjectLanguage, where: language.project_id == ^project_id, select: language.locale_code)
        |> Repo.all()
        |> MapSet.new(),
      assets: project_entity_ids(Asset, project_id, Enum.map(texts, & &1["vo_asset_id"])),
      sheets: project_entity_ids(Sheet, project_id, speaker_ids),
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
    current? = translated? and not is_nil(text["source_text_hash"]) and translated_source_hash == text["source_text_hash"]

    case text["status"] do
      "final" when not current? -> if(translated?, do: "review", else: "pending")
      status when status in ~w(pending draft in_progress review final) -> status
      _invalid -> if(translated?, do: "draft", else: "pending")
    end
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
