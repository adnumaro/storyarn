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
    languages = Localization.list_languages(project_id)

    locale_codes =
      case opts.languages do
        :all -> Enum.map(languages, & &1.locale_code)
        codes -> codes
      end

    %{
      languages: languages,
      strings: Localization.list_texts_for_export(project_id, locale_codes),
      glossary: Localization.list_glossary_for_export(project_id)
    }
  end

  defp maybe_load(:assets, _project_id, %{include_assets: false}), do: []

  defp maybe_load(:assets, project_id, _opts) do
    Assets.list_assets_for_export(project_id)
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

  defp count_languages(project_id, _opts) do
    Repo.aggregate(from(l in ProjectLanguage, where: l.project_id == ^project_id), :count)
  end

  defp count_localized_texts(_project_id, %{include_localization: false}), do: 0

  defp count_localized_texts(project_id, opts) do
    case opts.languages do
      :all ->
        Localization.count_texts(project_id)

      [] ->
        0

      locale_codes ->
        Repo.aggregate(
          from(lt in LocalizedText,
            where: lt.project_id == ^project_id and lt.locale_code in ^locale_codes
          ),
          :count
        )
    end
  end

  defp count_glossary_entries(_project_id, %{include_localization: false}), do: 0

  defp count_glossary_entries(project_id, _opts) do
    Repo.aggregate(from(g in GlossaryEntry, where: g.project_id == ^project_id), :count)
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
