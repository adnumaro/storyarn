defmodule Storyarn.Exports.DataCollector do
  @moduledoc """
  Loads project data for export.

  Provides two modes:
  - `collect/2` — In-memory mode for small projects, validation, and tests
  - `count_entities/2` — Entity counting for progress estimation

  Streaming mode (`stream/2`) will be added in Phase E for large project support.
  """

  import Ecto.Query

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  @doc """
  Load all project data into memory for export.

  Returns a map with sections matching the export format structure.
  Each section respects the filtering options in `ExportOptions`.

  Accepts an optional `preloaded` map to reuse data already loaded by the
  Validator (e.g., `%{flows: flows_data}`). Only flows are shared — sheets
  need full block preloads that the validator doesn't load.
  """
  def collect(project_id, %ExportOptions{} = opts, preloaded \\ %{}) do
    %{
      project: load_project(project_id),
      sheets: maybe_load(:sheets, project_id, opts),
      flows: maybe_load_preloaded(:flows, project_id, opts, preloaded),
      scenes: maybe_load(:scenes, project_id, opts),
      screenplays: maybe_load(:screenplays, project_id, opts),
      localization: maybe_load(:localization, project_id, opts),
      assets: maybe_load(:assets, project_id, opts)
    }
  end

  @doc """
  Count entities in a project for progress estimation.
  """
  def count_entities(project_id, %ExportOptions{} = opts) do
    counts = %{
      sheets: count_if(:sheets, project_id, opts),
      sheet_blocks: count_sheet_blocks(project_id, opts),
      table_columns: count_table_columns(project_id, opts),
      table_rows: count_table_rows(project_id, opts),
      flows: count_if(:flows, project_id, opts),
      nodes: count_nodes(project_id, opts),
      flow_connections: count_flow_connections(project_id, opts),
      scenes: count_if(:scenes, project_id, opts),
      scene_layers: count_scene_children(SceneLayer, project_id, opts),
      scene_pins: count_scene_children(ScenePin, project_id, opts),
      scene_zones: count_scene_children(SceneZone, project_id, opts),
      scene_connections: count_scene_children(SceneConnection, project_id, opts),
      scene_annotations: count_scene_children(SceneAnnotation, project_id, opts),
      screenplays: count_if(:screenplays, project_id, opts),
      screenplay_elements: count_screenplay_elements(project_id, opts),
      assets: count_if(:assets, project_id, opts),
      languages: count_languages(project_id, opts),
      localized_texts: count_localized_texts(project_id, opts),
      glossary_entries: count_glossary_entries(project_id, opts)
    }

    Map.put(counts, :total_rows, counts |> Map.values() |> Enum.sum())
  end

  @doc """
  Estimate the database bytes that the in-memory export path would materialize.

  The estimate is computed inside PostgreSQL from each row's logical JSON byte
  length, so compressed or TOASTed text and JSON fields are fully counted before
  Ecto loads them into the request process. It deliberately includes all
  selected rows even when a target serializer may omit some fields.
  """
  def estimate_source_bytes(project_id, %ExportOptions{} = opts) do
    bytes = %{
      project: row_bytes(from(p in Project, where: p.id == ^project_id)),
      sheets: section_row_bytes(:sheets, Sheet, project_id, opts),
      sheet_avatars: sheet_avatar_bytes(project_id, opts),
      sheet_blocks: sheet_child_bytes(Block, project_id, opts),
      table_columns: table_child_bytes(TableColumn, project_id, opts),
      table_rows: table_child_bytes(TableRow, project_id, opts),
      flows: section_row_bytes(:flows, Flow, project_id, opts),
      nodes: flow_node_bytes(project_id, opts),
      flow_connections: flow_child_bytes(FlowConnection, project_id, opts),
      scenes: section_row_bytes(:scenes, Scene, project_id, opts),
      scene_layers: scene_child_bytes(SceneLayer, project_id, opts),
      scene_pins: scene_child_bytes(ScenePin, project_id, opts),
      scene_zones: scene_child_bytes(SceneZone, project_id, opts),
      scene_connections: scene_child_bytes(SceneConnection, project_id, opts),
      scene_annotations: scene_child_bytes(SceneAnnotation, project_id, opts),
      screenplays: screenplay_bytes(project_id, opts),
      screenplay_elements: screenplay_element_bytes(project_id, opts),
      assets: asset_bytes(project_id, opts),
      languages: language_bytes(project_id, opts),
      localized_texts: localized_text_bytes(project_id, opts),
      glossary_entries: glossary_entry_bytes(project_id, opts)
    }

    Map.put(bytes, :total_bytes, bytes |> Map.values() |> Enum.sum())
  end

  # -- Project --

  defp load_project(project_id) do
    Projects.get_project!(project_id)
  end

  defp maybe_load_preloaded(section, project_id, opts, preloaded) do
    case Map.get(preloaded, section) do
      nil -> maybe_load(section, project_id, opts)
      data -> data
    end
  end

  # -- Section loaders --

  defp maybe_load(:sheets, _project_id, %{include_sheets: false}), do: []

  defp maybe_load(:sheets, project_id, opts) do
    filter_ids = if opts.sheet_ids == :all, do: :all, else: opts.sheet_ids
    Sheets.list_sheets_for_export(project_id, filter_ids: filter_ids)
  end

  defp maybe_load(:flows, _project_id, %{include_flows: false}), do: []

  defp maybe_load(:flows, project_id, opts) do
    filter_ids = if opts.flow_ids == :all, do: :all, else: opts.flow_ids
    Flows.list_flows_for_export(project_id, filter_ids: filter_ids)
  end

  defp maybe_load(:scenes, _project_id, %{include_scenes: false}), do: []

  defp maybe_load(:scenes, project_id, opts) do
    filter_ids = if opts.scene_ids == :all, do: :all, else: opts.scene_ids
    Scenes.list_scenes_for_export(project_id, filter_ids: filter_ids)
  end

  defp maybe_load(:screenplays, _project_id, %{include_screenplays: false}), do: []

  defp maybe_load(:screenplays, project_id, _opts) do
    Screenplays.list_screenplays_for_export(project_id)
  end

  defp maybe_load(:localization, _project_id, %{include_localization: false}),
    do: %{languages: [], strings: [], glossary: []}

  defp maybe_load(:localization, project_id, opts) do
    languages =
      if opts.format == :storyarn,
        do: Localization.list_languages_for_backup(project_id),
        else: Localization.list_languages(project_id)

    locale_codes =
      case opts.languages do
        :all -> Enum.map(languages, & &1.locale_code)
        codes -> requested_locale_codes(codes, languages)
      end

    %{
      languages: languages,
      strings:
        if(opts.format == :storyarn,
          do: Localization.list_texts_for_backup(project_id, locale_codes),
          else: Localization.list_texts_for_export(project_id, locale_codes, opts)
        ),
      glossary: Localization.list_glossary_for_export(project_id)
    }
  end

  defp maybe_load(:assets, _project_id, %{include_assets: false}), do: []

  defp maybe_load(:assets, project_id, _opts) do
    Assets.list_assets_for_export(project_id)
  end

  defp requested_locale_codes(:all, languages), do: Enum.map(languages, & &1.locale_code)

  defp requested_locale_codes(codes, languages) do
    available = MapSet.new(languages, & &1.locale_code)

    codes
    |> Enum.filter(&MapSet.member?(available, &1))
    |> Enum.uniq()
  end

  # -- Counters --

  defp count_if(:sheets, _project_id, %{include_sheets: false}), do: 0
  defp count_if(:flows, _project_id, %{include_flows: false}), do: 0
  defp count_if(:scenes, _project_id, %{include_scenes: false}), do: 0
  defp count_if(:screenplays, _project_id, %{include_screenplays: false}), do: 0
  defp count_if(:assets, _project_id, %{include_assets: false}), do: 0

  defp count_if(:sheets, project_id, opts), do: count_sheets(project_id, opts)
  defp count_if(:flows, project_id, opts), do: count_flows(project_id, opts)
  defp count_if(:scenes, project_id, opts), do: count_scenes(project_id, opts)
  defp count_if(:screenplays, project_id, _opts), do: Screenplays.count_screenplays(project_id)
  defp count_if(:assets, project_id, _opts), do: Assets.count_assets(project_id)

  defp count_sheets(project_id, %{sheet_ids: :all}), do: Sheets.count_sheets(project_id)

  defp count_sheets(_project_id, %{sheet_ids: []}), do: 0

  defp count_sheets(project_id, %{sheet_ids: sheet_ids}) do
    Repo.aggregate(
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and s.id in ^sheet_ids
      ),
      :count
    )
  end

  defp count_sheet_blocks(_project_id, %{include_sheets: false}), do: 0

  defp count_sheet_blocks(project_id, opts) do
    Block
    |> project_sheet_children_query(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp count_table_columns(_project_id, %{include_sheets: false}), do: 0

  defp count_table_columns(project_id, opts) do
    TableColumn
    |> project_table_children_query(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp count_table_rows(_project_id, %{include_sheets: false}), do: 0

  defp count_table_rows(project_id, opts) do
    TableRow
    |> project_table_children_query(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp count_flows(project_id, %{flow_ids: :all}), do: Flows.count_flows(project_id)

  defp count_flows(_project_id, %{flow_ids: []}), do: 0

  defp count_flows(project_id, %{flow_ids: flow_ids}) do
    Repo.aggregate(
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and f.id in ^flow_ids
      ),
      :count
    )
  end

  defp count_nodes(_project_id, %{include_flows: false}), do: 0
  defp count_nodes(project_id, %{flow_ids: :all}), do: Flows.count_nodes_for_project(project_id)
  defp count_nodes(_project_id, %{flow_ids: []}), do: 0

  defp count_nodes(project_id, %{flow_ids: flow_ids}) do
    Repo.aggregate(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and
            f.id in ^flow_ids
      ),
      :count
    )
  end

  defp count_flow_connections(_project_id, %{include_flows: false}), do: 0

  defp count_flow_connections(project_id, opts) do
    FlowConnection
    |> project_flow_children_query(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp count_scenes(project_id, %{scene_ids: :all}), do: Scenes.count_scenes(project_id)

  defp count_scenes(_project_id, %{scene_ids: []}), do: 0

  defp count_scenes(project_id, %{scene_ids: scene_ids}) do
    Repo.aggregate(
      from(s in Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and s.id in ^scene_ids
      ),
      :count
    )
  end

  defp count_scene_children(_schema, _project_id, %{include_scenes: false}), do: 0

  defp count_scene_children(schema, project_id, opts) do
    schema
    |> project_scene_children_query(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp count_screenplay_elements(_project_id, %{include_screenplays: false}), do: 0

  defp count_screenplay_elements(project_id, _opts) do
    Repo.aggregate(
      from(e in ScreenplayElement,
        join: sp in Screenplay,
        on: e.screenplay_id == sp.id,
        where: sp.project_id == ^project_id and is_nil(sp.deleted_at)
      ),
      :count
    )
  end

  defp count_languages(_project_id, %{include_localization: false}), do: 0

  defp count_languages(project_id, opts) do
    query = from(l in ProjectLanguage, where: l.project_id == ^project_id)
    query = if opts.format == :storyarn, do: query, else: where(query, [l], is_nil(l.archived_at))
    Repo.aggregate(query, :count)
  end

  defp count_localized_texts(_project_id, %{include_localization: false}), do: 0

  defp count_localized_texts(project_id, opts) do
    if opts.format == :storyarn do
      case opts.languages do
        :all ->
          Localization.count_texts(project_id, include_archived: true)

        [] ->
          0

        locale_codes ->
          Repo.aggregate(
            from(lt in LocalizedText, where: lt.project_id == ^project_id and lt.locale_code in ^locale_codes),
            :count
          )
      end
    else
      active_languages = Localization.list_languages(project_id)
      locale_codes = requested_locale_codes(opts.languages, active_languages)
      Localization.count_texts_for_export(project_id, locale_codes, opts)
    end
  end

  defp count_glossary_entries(_project_id, %{include_localization: false}), do: 0

  defp count_glossary_entries(project_id, _opts) do
    Repo.aggregate(from(g in GlossaryEntry, where: g.project_id == ^project_id), :count)
  end

  # -- Source byte estimates --

  defp section_row_bytes(:sheets, _schema, _project_id, %{include_sheets: false}), do: 0
  defp section_row_bytes(:flows, _schema, _project_id, %{include_flows: false}), do: 0
  defp section_row_bytes(:scenes, _schema, _project_id, %{include_scenes: false}), do: 0

  defp section_row_bytes(:sheets, Sheet, project_id, opts) do
    project_id
    |> project_sheets_query(opts)
    |> row_bytes()
  end

  defp section_row_bytes(:flows, Flow, project_id, opts) do
    project_id
    |> project_flows_query(opts)
    |> row_bytes()
  end

  defp section_row_bytes(:scenes, Scene, project_id, opts) do
    project_id
    |> project_scenes_query(opts)
    |> row_bytes()
  end

  defp sheet_avatar_bytes(_project_id, %{include_sheets: false}), do: 0

  defp sheet_avatar_bytes(project_id, %{sheet_ids: sheet_ids}) do
    query =
      from(avatar in SheetAvatar,
        join: s in Sheet,
        on: avatar.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at)
      )

    case_result =
      case sheet_ids do
        :all -> query
        [] -> where(query, false)
        ids -> where(query, [_avatar, s], s.id in ^ids)
      end

    row_bytes(case_result)
  end

  defp sheet_child_bytes(_schema, _project_id, %{include_sheets: false}), do: 0

  defp sheet_child_bytes(schema, project_id, opts) do
    schema
    |> project_sheet_children_query(project_id, opts)
    |> row_bytes()
  end

  defp table_child_bytes(_schema, _project_id, %{include_sheets: false}), do: 0

  defp table_child_bytes(schema, project_id, opts) do
    schema
    |> project_table_children_query(project_id, opts)
    |> row_bytes()
  end

  defp flow_node_bytes(_project_id, %{include_flows: false}), do: 0

  defp flow_node_bytes(project_id, opts) do
    project_id
    |> project_flow_nodes_query(opts)
    |> row_bytes()
  end

  defp flow_child_bytes(_schema, _project_id, %{include_flows: false}), do: 0

  defp flow_child_bytes(schema, project_id, opts) do
    schema
    |> project_flow_children_query(project_id, opts)
    |> row_bytes()
  end

  defp scene_child_bytes(_schema, _project_id, %{include_scenes: false}), do: 0

  defp scene_child_bytes(schema, project_id, opts) do
    schema
    |> project_scene_children_query(project_id, opts)
    |> row_bytes()
  end

  defp screenplay_bytes(_project_id, %{include_screenplays: false}), do: 0

  defp screenplay_bytes(project_id, _opts) do
    row_bytes(from(sp in Screenplay, where: sp.project_id == ^project_id and is_nil(sp.deleted_at)))
  end

  defp screenplay_element_bytes(_project_id, %{include_screenplays: false}), do: 0

  defp screenplay_element_bytes(project_id, _opts) do
    row_bytes(
      from(e in ScreenplayElement,
        join: sp in Screenplay,
        on: e.screenplay_id == sp.id,
        where: sp.project_id == ^project_id and is_nil(sp.deleted_at)
      )
    )
  end

  defp asset_bytes(_project_id, %{include_assets: false}), do: 0

  defp asset_bytes(project_id, _opts) do
    row_bytes(from(a in Asset, where: a.project_id == ^project_id))
  end

  defp language_bytes(_project_id, %{include_localization: false}), do: 0

  defp language_bytes(project_id, opts) do
    project_id
    |> project_languages_query(opts)
    |> row_bytes()
  end

  defp localized_text_bytes(_project_id, %{include_localization: false}), do: 0

  defp localized_text_bytes(project_id, opts) do
    project_id
    |> project_localized_texts_query(opts)
    |> row_bytes()
  end

  defp glossary_entry_bytes(_project_id, %{include_localization: false}), do: 0

  defp glossary_entry_bytes(project_id, _opts) do
    row_bytes(from(g in GlossaryEntry, where: g.project_id == ^project_id))
  end

  defp row_bytes(query) do
    Repo.one(
      from(row in query,
        select: fragment("COALESCE(SUM(octet_length(to_jsonb(?)::text)), 0)", row)
      )
    )
  end

  defp project_sheets_query(project_id, %{sheet_ids: sheet_ids}) do
    query = from(s in Sheet, where: s.project_id == ^project_id and is_nil(s.deleted_at))

    case sheet_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [s], s.id in ^ids)
    end
  end

  defp project_flows_query(project_id, %{flow_ids: flow_ids}) do
    query = from(f in Flow, where: f.project_id == ^project_id and is_nil(f.deleted_at))

    case flow_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [f], f.id in ^ids)
    end
  end

  defp project_flow_nodes_query(project_id, %{flow_ids: flow_ids}) do
    query =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at)
      )

    case flow_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_node, f], f.id in ^ids)
    end
  end

  defp project_scenes_query(project_id, %{scene_ids: scene_ids}) do
    query = from(s in Scene, where: s.project_id == ^project_id and is_nil(s.deleted_at))

    case scene_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [s], s.id in ^ids)
    end
  end

  defp project_languages_query(project_id, opts) do
    query = from(l in ProjectLanguage, where: l.project_id == ^project_id)
    if opts.format == :storyarn, do: query, else: where(query, [l], is_nil(l.archived_at))
  end

  defp project_localized_texts_query(project_id, opts) do
    locale_codes =
      case opts.languages do
        :all when opts.format == :storyarn -> :all
        languages when opts.format == :storyarn -> languages
        languages -> requested_locale_codes(languages, Localization.list_languages(project_id))
      end

    query = from(lt in LocalizedText, where: lt.project_id == ^project_id)

    case locale_codes do
      :all -> query
      [] -> where(query, false)
      codes -> where(query, [lt], lt.locale_code in ^codes)
    end
  end

  defp project_sheet_children_query(schema, project_id, %{sheet_ids: sheet_ids}) do
    query =
      from(child in schema,
        join: s in Sheet,
        on: child.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(child.deleted_at)
      )

    case sheet_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_child, s], s.id in ^ids)
    end
  end

  defp project_table_children_query(schema, project_id, %{sheet_ids: sheet_ids}) do
    query =
      from(child in schema,
        join: b in Block,
        on: child.block_id == b.id,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at)
      )

    case sheet_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_child, _b, s], s.id in ^ids)
    end
  end

  defp project_flow_children_query(schema, project_id, %{flow_ids: flow_ids}) do
    query =
      from(child in schema,
        join: f in Flow,
        on: child.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at)
      )

    case flow_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_child, f], f.id in ^ids)
    end
  end

  defp project_scene_children_query(schema, project_id, %{scene_ids: scene_ids}) do
    query =
      from(child in schema,
        join: s in Scene,
        on: child.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at)
      )

    case scene_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_child, s], s.id in ^ids)
    end
  end
end
