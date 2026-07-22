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
  alias Storyarn.Flows.SequenceConfig
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

  @default_source_byte_query_timeout_ms 5_000
  @source_byte_stream_rows 128
  @source_byte_sections [
    :project,
    :sheets,
    :sheet_avatars,
    :sheet_blocks,
    :table_columns,
    :table_rows,
    :flows,
    :nodes,
    :sequence_configs,
    :flow_connections,
    :scenes,
    :scene_layers,
    :scene_pins,
    :scene_zones,
    :scene_connections,
    :scene_annotations,
    :screenplays,
    :screenplay_elements,
    :assets,
    :languages,
    :localized_texts,
    :glossary_entries
  ]

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
  def estimate_source_bytes(project_id, %ExportOptions{} = opts, estimate_opts \\ []) do
    max_bytes = Keyword.get(estimate_opts, :max_bytes, :infinity)
    timeout_ms = Keyword.get(estimate_opts, :timeout, @default_source_byte_query_timeout_ms)

    if timeout_ms <= 0 do
      {:error, :timeout}
    else
      deadline = System.monotonic_time(:millisecond) + timeout_ms

      try do
        case Repo.transaction(
               fn ->
                 configure_source_byte_statement_timeout(timeout_ms)
                 queries = source_byte_queries(project_id, opts)
                 remaining_source_timeout!(deadline)
                 sum_source_bytes(queries, max_bytes, deadline)
               end,
               timeout: timeout_ms
             ) do
          {:ok, bytes} -> {:ok, bytes}
          {:error, :source_byte_estimate_timeout} -> {:error, :timeout}
        end
      rescue
        DBConnection.ConnectionError ->
          {:error, :timeout}

        error in Postgrex.Error ->
          if error.postgres && error.postgres.code == :query_canceled do
            {:error, :timeout}
          else
            reraise error, __STACKTRACE__
          end
      end
    end
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

  defp configure_source_byte_statement_timeout(timeout_ms) do
    timeout = Integer.to_string(timeout_ms) <> "ms"
    Repo.query!("SELECT set_config('statement_timeout', $1, true)", [timeout])
  end

  defp source_byte_queries(project_id, opts) do
    [
      {:project, from(p in Project, where: p.id == ^project_id)},
      {:sheets, section_row_query(:sheets, Sheet, project_id, opts)},
      {:sheet_avatars, sheet_avatar_query(project_id, opts)},
      {:sheet_blocks, sheet_child_query(Block, project_id, opts)},
      {:table_columns, table_child_query(TableColumn, project_id, opts)},
      {:table_rows, table_child_query(TableRow, project_id, opts)},
      {:flows, section_row_query(:flows, Flow, project_id, opts)},
      {:nodes, flow_node_query(project_id, opts)},
      {:sequence_configs, sequence_config_query(project_id, opts)},
      {:flow_connections, flow_child_query(FlowConnection, project_id, opts)},
      {:scenes, section_row_query(:scenes, Scene, project_id, opts)},
      {:scene_layers, scene_child_query(SceneLayer, project_id, opts)},
      {:scene_pins, scene_child_query(ScenePin, project_id, opts)},
      {:scene_zones, scene_child_query(SceneZone, project_id, opts)},
      {:scene_connections, scene_child_query(SceneConnection, project_id, opts)},
      {:scene_annotations, scene_child_query(SceneAnnotation, project_id, opts)},
      {:screenplays, screenplay_query(project_id, opts)},
      {:screenplay_elements, screenplay_element_query(project_id, opts)},
      {:assets, asset_query(project_id, opts)},
      {:languages, language_query(project_id, opts)},
      {:localized_texts, localized_text_query(project_id, opts)},
      {:glossary_entries, glossary_entry_query(project_id, opts)}
    ]
  end

  defp sum_source_bytes(queries, max_bytes, deadline) do
    initial_bytes = Map.new(@source_byte_sections, &{&1, 0})

    {bytes, total_bytes, truncated?} =
      Enum.reduce_while(queries, {initial_bytes, 0, false}, fn {section, query}, {bytes, total_bytes, false} ->
        remaining_bytes = remaining_source_bytes(max_bytes, total_bytes)
        section_bytes = query_source_bytes(query, remaining_bytes, deadline)
        total_bytes = total_bytes + section_bytes
        bytes = Map.put(bytes, section, section_bytes)

        if source_limit_exceeded?(max_bytes, total_bytes) do
          {:halt, {bytes, total_bytes, true}}
        else
          {:cont, {bytes, total_bytes, false}}
        end
      end)

    bytes
    |> Map.put(:total_bytes, total_bytes)
    |> Map.put(:truncated?, truncated?)
  end

  defp query_source_bytes(nil, _max_bytes, _deadline), do: 0

  defp query_source_bytes(query, max_bytes, deadline) do
    timeout = remaining_source_timeout!(deadline)

    query
    |> select([row], fragment("octet_length(to_jsonb(?)::text)", row))
    |> Repo.stream(max_rows: @source_byte_stream_rows, timeout: timeout)
    |> Enum.reduce_while(0, fn row_bytes, total_bytes ->
      remaining_source_timeout!(deadline)
      next_total = total_bytes + row_bytes

      if source_limit_exceeded?(max_bytes, next_total) do
        {:halt, max_bytes + 1}
      else
        {:cont, next_total}
      end
    end)
  end

  defp remaining_source_timeout!(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      remaining
    else
      Repo.rollback(:source_byte_estimate_timeout)
    end
  end

  defp remaining_source_bytes(:infinity, _total_bytes), do: :infinity
  defp remaining_source_bytes(max_bytes, total_bytes), do: max_bytes - total_bytes

  defp source_limit_exceeded?(:infinity, _total_bytes), do: false
  defp source_limit_exceeded?(max_bytes, total_bytes), do: total_bytes > max_bytes

  defp section_row_query(:sheets, _schema, _project_id, %{include_sheets: false}), do: nil
  defp section_row_query(:flows, _schema, _project_id, %{include_flows: false}), do: nil
  defp section_row_query(:scenes, _schema, _project_id, %{include_scenes: false}), do: nil

  defp section_row_query(:sheets, Sheet, project_id, opts), do: project_sheets_query(project_id, opts)
  defp section_row_query(:flows, Flow, project_id, opts), do: project_flows_query(project_id, opts)
  defp section_row_query(:scenes, Scene, project_id, opts), do: project_scenes_query(project_id, opts)

  defp sheet_avatar_query(_project_id, %{include_sheets: false}), do: nil

  defp sheet_avatar_query(project_id, %{sheet_ids: sheet_ids}) do
    query =
      from(avatar in SheetAvatar,
        join: sheet in Sheet,
        on: avatar.sheet_id == sheet.id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at)
      )

    case sheet_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_avatar, sheet], sheet.id in ^ids)
    end
  end

  defp sheet_child_query(_schema, _project_id, %{include_sheets: false}), do: nil
  defp sheet_child_query(schema, project_id, opts), do: project_sheet_children_query(schema, project_id, opts)

  defp table_child_query(_schema, _project_id, %{include_sheets: false}), do: nil
  defp table_child_query(schema, project_id, opts), do: project_table_children_query(schema, project_id, opts)

  defp flow_node_query(_project_id, %{include_flows: false}), do: nil
  defp flow_node_query(project_id, opts), do: project_flow_nodes_query(project_id, opts)

  defp flow_child_query(_schema, _project_id, %{include_flows: false}), do: nil
  defp flow_child_query(schema, project_id, opts), do: project_flow_children_query(schema, project_id, opts)

  defp scene_child_query(_schema, _project_id, %{include_scenes: false}), do: nil
  defp scene_child_query(schema, project_id, opts), do: project_scene_children_query(schema, project_id, opts)

  defp sequence_config_query(_project_id, %{include_flows: false}), do: nil

  defp sequence_config_query(project_id, %{flow_ids: flow_ids}) do
    query =
      from(config in SequenceConfig,
        join: node in FlowNode,
        on: config.flow_node_id == node.id,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at) and is_nil(node.deleted_at)
      )

    case flow_ids do
      :all -> query
      [] -> where(query, false)
      ids -> where(query, [_config, _node, flow], flow.id in ^ids)
    end
  end

  defp screenplay_query(_project_id, %{include_screenplays: false}), do: nil

  defp screenplay_query(project_id, _opts) do
    from(screenplay in Screenplay,
      where: screenplay.project_id == ^project_id and is_nil(screenplay.deleted_at)
    )
  end

  defp screenplay_element_query(_project_id, %{include_screenplays: false}), do: nil

  defp screenplay_element_query(project_id, _opts) do
    from(element in ScreenplayElement,
      join: screenplay in Screenplay,
      on: element.screenplay_id == screenplay.id,
      where: screenplay.project_id == ^project_id and is_nil(screenplay.deleted_at)
    )
  end

  defp asset_query(_project_id, %{include_assets: false}), do: nil
  defp asset_query(project_id, _opts), do: from(asset in Asset, where: asset.project_id == ^project_id)

  defp language_query(_project_id, %{include_localization: false}), do: nil
  defp language_query(project_id, opts), do: project_languages_query(project_id, opts)

  defp localized_text_query(_project_id, %{include_localization: false}), do: nil
  defp localized_text_query(project_id, opts), do: project_localized_texts_query(project_id, opts)

  defp glossary_entry_query(_project_id, %{include_localization: false}), do: nil

  defp glossary_entry_query(project_id, _opts) do
    from(entry in GlossaryEntry, where: entry.project_id == ^project_id)
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

  defp project_localized_texts_query(project_id, %{format: :storyarn} = opts) do
    locale_codes =
      requested_locale_codes(opts.languages, Localization.list_languages_for_backup(project_id))

    from(text in LocalizedText,
      where: text.project_id == ^project_id and text.locale_code in ^locale_codes
    )
  end

  defp project_localized_texts_query(project_id, opts) do
    locale_codes = requested_locale_codes(opts.languages, Localization.list_languages(project_id))
    Localization.texts_for_export_query(project_id, locale_codes, opts)
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
