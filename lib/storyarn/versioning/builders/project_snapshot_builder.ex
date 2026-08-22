defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilder do
  @moduledoc """
  Builds portable project-template snapshots.

  The resulting map captures the active sheets, flows, scenes, localization,
  tree structure, and portable asset metadata required by ProjectTemplates.
  Canonical project snapshots use `SnapshotObjectFormat` and do not restore
  through this builder.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.FlowReadModel
  alias Storyarn.Projects.LocalizationReadModel
  alias Storyarn.Projects.LocalizationSourceContract, as: SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.ReferencedTombstones

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
      |> build_consistent_snapshot(Keyword.fetch!(opts, :localization_scope), :strict)
    else
      raise ArgumentError, "project snapshot capture requires a database transaction"
    end
  end

  @doc false
  @spec build_canonical_snapshot_in_transaction(integer(), keyword()) :: map()
  def build_canonical_snapshot_in_transaction(project_id, opts) when is_list(opts) do
    if Repo.in_transaction?() do
      snapshot =
        project_id
        |> lock_active_project_for_snapshot!()
        |> build_consistent_snapshot(Keyword.fetch!(opts, :localization_scope), :canonical)

      if Keyword.get(opts, :include_referenced_tombstones, false),
        do: Map.put(snapshot, "referenced_tombstones", ReferencedTombstones.capture!(project_id)),
        else: snapshot
    else
      raise ArgumentError, "canonical project snapshot capture requires a database transaction"
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

  defp build_consistent_snapshot(project, localization_scope, mode) do
    project_id = project.id
    sheets = Sheets.list_sheets_for_export(project_id)
    flows = FlowReadModel.list_flows_for_export(project_id)
    scenes = Scenes.list_scenes_for_export(project_id)

    {languages, texts} = localization_inventory(project_id, localization_scope, mode)

    glossary = LocalizationReadModel.list_glossary_for_export(project_id)

    sheet_snapshots = build_sheet_snapshots(sheets, mode)
    flow_snapshots = build_flow_snapshots(flows, mode)
    scene_snapshots = build_scene_snapshots(scenes, mode)

    text_snapshots =
      texts
      |> Enum.map(&text_to_snapshot/1)
      |> maybe_merge_nested_runtime_localization(sheet_snapshots, flow_snapshots, mode)

    {asset_blob_hashes, asset_metadata} =
      localization_asset_metadata(project_id, text_snapshots, mode)

    entity_counts = %{
      "sheets" => length(sheets),
      "flows" => length(flows),
      "scenes" => length(scenes),
      "languages" => length(languages),
      "localized_texts" => length(text_snapshots),
      "glossary_entries" => length(glossary)
    }

    %{
      "format_version" => 2,
      "project" => project_to_snapshot(project),
      "entity_counts" => entity_counts,
      "asset_blob_hashes" => asset_blob_hashes,
      "asset_metadata" => asset_metadata,
      "sheets" => sheet_snapshots,
      "flows" => flow_snapshots,
      "scenes" => scene_snapshots,
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
        "texts" => text_snapshots,
        "glossary" => Enum.map(glossary, &glossary_entry_to_snapshot/1)
      }
    }
  end

  defp build_sheet_snapshots(sheets, :strict) do
    build_entity_snapshots(sheets, &SheetBuilder.build_snapshot/1)
  end

  defp build_sheet_snapshots(sheets, :canonical) do
    build_entity_snapshots(sheets, &SheetBuilder.build_capture_snapshot/1)
  end

  defp build_flow_snapshots(flows, :strict) do
    build_entity_snapshots(flows, &FlowBuilder.build_snapshot/1)
  end

  defp build_flow_snapshots(flows, :canonical) do
    build_entity_snapshots(flows, &FlowBuilder.build_capture_snapshot/1)
  end

  defp build_scene_snapshots(scenes, :strict) do
    build_entity_snapshots(scenes, &SceneBuilder.build_snapshot/1)
  end

  defp build_scene_snapshots(scenes, :canonical) do
    build_entity_snapshots(scenes, &SceneBuilder.build_capture_snapshot/1)
  end

  defp build_entity_snapshots(entities, build_fun) do
    Enum.map(entities, fn entity ->
      %{"id" => entity.id, "snapshot" => build_fun.(entity)}
    end)
  end

  defp maybe_merge_nested_runtime_localization(rows, sheet_snapshots, flow_snapshots, :strict) do
    merge_nested_runtime_localization(rows, sheet_snapshots, flow_snapshots)
  end

  defp maybe_merge_nested_runtime_localization(rows, _sheet_snapshots, _flow_snapshots, :canonical), do: rows

  defp merge_nested_runtime_localization(global_rows, sheet_snapshots, flow_snapshots) do
    active_global_keys =
      global_rows
      |> Enum.filter(&is_nil(&1["archived_at"]))
      |> MapSet.new(&runtime_localization_key/1)

    missing_rows =
      (sheet_snapshots ++ flow_snapshots)
      |> Enum.flat_map(&get_in(&1, ["snapshot", "localization"]))
      |> Enum.reject(&MapSet.member?(active_global_keys, runtime_localization_key(&1)))
      |> Enum.map(&put_source_contract_metadata/1)
      |> Enum.sort_by(&runtime_localization_key/1)

    missing_keys = MapSet.new(missing_rows, &runtime_localization_key/1)

    retained_global_rows =
      Enum.reject(global_rows, fn row ->
        not is_nil(row["archived_at"]) and
          MapSet.member?(missing_keys, runtime_localization_key(row))
      end)

    retained_global_rows ++ missing_rows
  end

  defp runtime_localization_key(row) do
    {
      row["source_type"],
      row["source_id"],
      row["source_field"],
      row["locale_code"]
    }
  end

  defp put_source_contract_metadata(row) do
    metadata = SourceContract.field_metadata(row["source_type"], row["source_field"])

    row
    |> Map.put("content_role", metadata.content_role)
    |> Map.put("vo_eligible", metadata.vo_eligible)
  end

  defp localization_inventory(project_id, :active, :canonical) do
    {LocalizationReadModel.list_languages(project_id),
     LocalizationReadModel.list_texts_for_canonical_snapshot(project_id)}
  end

  defp localization_inventory(project_id, :active, _mode) do
    languages = LocalizationReadModel.list_languages(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes == [],
        do: [],
        else: LocalizationReadModel.list_texts_for_export(project_id, locale_codes)

    {languages, texts}
  end

  defp localization_inventory(project_id, :backup, _mode) do
    languages = LocalizationReadModel.list_languages_for_backup(project_id)
    locale_codes = Enum.map(languages, & &1.locale_code)

    texts =
      if locale_codes == [],
        do: [],
        else: LocalizationReadModel.list_texts_for_backup(project_id, locale_codes)

    {languages, texts}
  end

  defp localization_asset_metadata(project_id, texts, :strict) do
    texts
    |> Enum.map(& &1["vo_asset_id"])
    |> AssetHashResolver.resolve_hashes_for_project!(project_id)
  end

  defp localization_asset_metadata(project_id, texts, :canonical) do
    texts
    |> Enum.map(fn text ->
      {text["vo_asset_id"],
       %{
         entity_type: text["source_type"],
         entity_id: text["source_id"],
         source_field: "vo_asset_id",
         container_type: :project,
         container_id: project_id
       }}
    end)
    |> AssetHashResolver.resolve_hashes_for_project_capture(project_id)
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
