defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilder do
  @moduledoc """
  Builds and restores project-level snapshots.

  A project snapshot captures the full state of all sheets, flows, and scenes
  using the per-entity builders for serialization and restoration.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Storyarn.{Flows, Localization, Repo, Scenes, Sheets}
  alias Storyarn.Localization.{GlossaryEntry, LocalizedText, ProjectLanguage}
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.Builders.{FlowBuilder, SceneBuilder, SheetBuilder}

  @doc """
  Builds a full project snapshot containing all non-deleted entities.

  Returns a map with format_version, entity_counts, and per-entity-type snapshots.
  """
  @spec build_snapshot(integer()) :: map()
  def build_snapshot(project_id) do
    sheets = Sheets.list_sheets_for_export(project_id)
    flows = Flows.list_flows_for_export(project_id)
    scenes = Scenes.list_scenes_for_export(project_id)

    languages = Localization.list_languages(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes != [],
        do: Localization.list_texts_for_export(project_id, locale_codes),
        else: []

    glossary = Localization.list_glossary_for_export(project_id)

    entity_counts = %{
      "sheets" => length(sheets),
      "flows" => length(flows),
      "scenes" => length(scenes),
      "languages" => length(languages),
      "localized_texts" => length(texts),
      "glossary_entries" => length(glossary)
    }

    %{
      "format_version" => 1,
      "entity_counts" => entity_counts,
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
      "localization" => %{
        "languages" => Enum.map(languages, &language_to_snapshot/1),
        "texts" => Enum.map(texts, &text_to_snapshot/1),
        "glossary" => Enum.map(glossary, &glossary_entry_to_snapshot/1)
      }
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
  def restore_snapshot(project_id, snapshot, _opts \\ []) do
    Repo.transaction(
      fn ->
        results = %{
          sheets:
            restore_entities(
              project_id,
              snapshot,
              "sheets",
              &restore_sheet(&1, &2, project_id)
            ),
          flows:
            restore_entities(
              project_id,
              snapshot,
              "flows",
              &restore_flow(&1, &2, project_id)
            ),
          scenes:
            restore_entities(
              project_id,
              snapshot,
              "scenes",
              &restore_scene(&1, &2, project_id)
            )
        }

        restore_localization(project_id, snapshot)

        %{
          restored: count_restored(results),
          skipped: count_skipped(results),
          details: results
        }
      end,
      timeout: :timer.minutes(5)
    )
  end

  defp restore_entities(project_id, snapshot, entity_key, restore_fn) do
    entity_snapshots = Map.get(snapshot, entity_key, [])

    Enum.map(entity_snapshots, fn entry ->
      entity_id = entry["id"]

      case restore_fn.(entity_id, entry["snapshot"]) do
        {:ok, _entity} ->
          {:restored, entity_id}

        {:error, :not_found} ->
          {:skipped, entity_id}

        {:error, reason} ->
          Logger.warning(
            "Failed to restore #{entity_key} #{entity_id} in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback({:restore_failed, entity_key, entity_id, reason})
      end
    end)
  end

  defp restore_sheet(sheet_id, snapshot, project_id) do
    case Sheets.get_sheet(project_id, sheet_id) do
      nil -> {:error, :not_found}
      sheet -> SheetBuilder.restore_snapshot(sheet, snapshot)
    end
  end

  defp restore_flow(flow_id, snapshot, project_id) do
    case Flows.get_flow(project_id, flow_id) do
      nil -> {:error, :not_found}
      flow -> FlowBuilder.restore_snapshot(flow, snapshot)
    end
  end

  defp restore_scene(scene_id, snapshot, project_id) do
    case Scenes.get_scene(project_id, scene_id) do
      nil -> {:error, :not_found}
      scene -> SceneBuilder.restore_snapshot(scene, snapshot)
    end
  end

  defp count_restored(results) do
    Enum.sum(
      for {_key, entries} <- results do
        Enum.count(entries, fn {status, _} -> status == :restored end)
      end
    )
  end

  defp count_skipped(results) do
    Enum.sum(
      for {_key, entries} <- results do
        Enum.count(entries, fn {status, _} -> status == :skipped end)
      end
    )
  end

  # ========== Localization Snapshots ==========

  defp language_to_snapshot(language) do
    %{
      "locale_code" => language.locale_code,
      "name" => language.name,
      "is_source" => language.is_source,
      "position" => language.position
    }
  end

  defp text_to_snapshot(text) do
    %{
      "source_type" => text.source_type,
      "source_id" => text.source_id,
      "source_field" => text.source_field,
      "source_text" => text.source_text,
      "source_text_hash" => text.source_text_hash,
      "locale_code" => text.locale_code,
      "translated_text" => text.translated_text,
      "status" => text.status,
      "vo_status" => text.vo_status,
      "vo_asset_id" => text.vo_asset_id,
      "translator_notes" => text.translator_notes,
      "reviewer_notes" => text.reviewer_notes,
      "speaker_sheet_id" => text.speaker_sheet_id,
      "word_count" => text.word_count,
      "machine_translated" => text.machine_translated,
      "last_translated_at" => text.last_translated_at,
      "last_reviewed_at" => text.last_reviewed_at,
      "translated_by_id" => text.translated_by_id,
      "reviewed_by_id" => text.reviewed_by_id
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

  defp restore_localization(project_id, snapshot) do
    localization = snapshot["localization"]
    now = TimeHelpers.now()

    # Delete existing localization data (order: texts first due to no FK deps)
    from(lt in LocalizedText, where: lt.project_id == ^project_id) |> Repo.delete_all()
    from(g in GlossaryEntry, where: g.project_id == ^project_id) |> Repo.delete_all()
    from(l in ProjectLanguage, where: l.project_id == ^project_id) |> Repo.delete_all()

    restore_languages(project_id, Map.get(localization, "languages", []), now)
    restore_texts(project_id, Map.get(localization, "texts", []), now)
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
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectLanguage, entries)
  end

  defp restore_texts(_project_id, [], _now), do: :ok

  defp restore_texts(project_id, texts, now) do
    texts
    |> Enum.map(fn text ->
      %{
        project_id: project_id,
        source_type: text["source_type"],
        source_id: text["source_id"],
        source_field: text["source_field"],
        source_text: text["source_text"],
        source_text_hash: text["source_text_hash"],
        locale_code: text["locale_code"],
        translated_text: text["translated_text"],
        status: text["status"] || "pending",
        vo_status: text["vo_status"] || "none",
        vo_asset_id: text["vo_asset_id"],
        translator_notes: text["translator_notes"],
        reviewer_notes: text["reviewer_notes"],
        speaker_sheet_id: text["speaker_sheet_id"],
        word_count: text["word_count"],
        machine_translated: text["machine_translated"] || false,
        last_translated_at: text["last_translated_at"],
        last_reviewed_at: text["last_reviewed_at"],
        translated_by_id: text["translated_by_id"],
        reviewed_by_id: text["reviewed_by_id"],
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
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
