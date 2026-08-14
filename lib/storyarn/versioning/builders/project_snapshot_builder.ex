defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilder do
  @moduledoc """
  Builds portable project-template snapshots.

  The resulting map captures the active sheets, flows, scenes, localization,
  tree structure, and portable asset metadata required by ProjectTemplates.
  Canonical project snapshots use `SnapshotObjectFormat` and do not restore
  through this builder.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder

  @doc """
  Builds a portable project-template snapshot containing all active entities.

  Returns a map with format version, entity counts, and per-entity snapshots.
  """
  @spec build_snapshot(integer()) :: map()
  def build_snapshot(project_id) do
    case Repo.repeatable_read(
           fn -> build_snapshot_in_transaction(project_id) end,
           timeout: to_timeout(minute: 5)
         ) do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        raise "project snapshot transaction failed: #{inspect(reason)}"
    end
  end

  @doc false
  @spec build_snapshot_in_transaction(integer()) :: map()
  def build_snapshot_in_transaction(project_id) do
    build_snapshot_in_transaction(project_id, localization_scope: :backup)
  end

  @doc false
  @spec build_snapshot_in_transaction(integer(), keyword()) :: map()
  def build_snapshot_in_transaction(project_id, opts) when is_list(opts) do
    if Repo.in_transaction?() do
      project_id
      |> lock_active_project_for_snapshot!()
      |> build_consistent_snapshot(Keyword.fetch!(opts, :localization_scope))
    else
      raise ArgumentError, "project snapshot capture requires a database transaction"
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

  defp build_consistent_snapshot(project, localization_scope) do
    project_id = project.id
    sheets = Sheets.list_sheets_for_export(project_id)
    flows = Flows.list_flows_for_export(project_id)
    scenes = Scenes.list_scenes_for_export(project_id)

    {languages, texts} = localization_inventory(project_id, localization_scope)

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

  defp localization_inventory(project_id, :active) do
    languages = Localization.list_languages(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes == [],
        do: [],
        else: Localization.list_texts_for_export(project_id, locale_codes)

    {languages, texts}
  end

  defp localization_inventory(project_id, :backup) do
    languages = Localization.list_languages_for_backup(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes == [],
        do: [],
        else: Localization.list_texts_for_backup(project_id, locale_codes)

    {languages, texts}
  end

  defp localization_asset_metadata(project_id, texts) do
    texts
    |> Enum.map(& &1.vo_asset_id)
    |> AssetHashResolver.resolve_hashes_for_project!(project_id)
  end

  defp project_to_snapshot(project) do
    %{
      "name" => project.name,
      "description" => project.description,
      "project_type" => project.project_type,
      "project_subtype" => project.project_subtype,
      "project_type_other" => project.project_type_other,
      "settings" => project.settings,
      "auto_version_flows" => project.auto_version_flows,
      "auto_version_scenes" => project.auto_version_scenes,
      "auto_version_sheets" => project.auto_version_sheets
    }
  end

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
end
