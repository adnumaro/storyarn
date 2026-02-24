defmodule Storyarn.Exports.DataCollector do
  @moduledoc """
  Loads project data for export.

  Provides two modes:
  - `collect/2` — In-memory mode for small projects, validation, and tests
  - `count_entities/2` — Entity counting for progress estimation

  Streaming mode (`stream/2`) will be added in Phase E for large project support.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Repo

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Localization.{GlossaryEntry, LocalizedText, ProjectLanguage}
  alias Storyarn.Projects.Project
  alias Storyarn.Scenes.Scene
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}
  alias Storyarn.Sheets.{Block, Sheet}

  @doc """
  Load all project data into memory for export.

  Returns a map with sections matching the export format structure.
  Each section respects the filtering options in `ExportOptions`.
  """
  def collect(project_id, %ExportOptions{} = opts) do
    %{
      project: load_project(project_id),
      sheets: maybe_load(:sheets, project_id, opts),
      flows: maybe_load(:flows, project_id, opts),
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
    %{
      sheets: count_if(:sheets, project_id, opts),
      flows: count_if(:flows, project_id, opts),
      nodes: count_nodes(project_id, opts),
      scenes: count_if(:scenes, project_id, opts),
      screenplays: count_if(:screenplays, project_id, opts),
      assets: count_if(:assets, project_id, opts)
    }
  end

  # -- Project --

  defp load_project(project_id) do
    Repo.get!(Project, project_id)
  end

  # -- Section loaders --

  defp maybe_load(:sheets, _project_id, %{include_sheets: false}), do: []

  defp maybe_load(:sheets, project_id, opts) do
    query =
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        preload: [blocks: ^blocks_preload_query()],
        order_by: [asc: s.position, asc: s.name]
      )

    query
    |> maybe_filter_ids(opts.sheet_ids, :id)
    |> Repo.all()
  end

  defp maybe_load(:flows, _project_id, %{include_flows: false}), do: []

  defp maybe_load(:flows, project_id, opts) do
    nodes_query = from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.id])

    query =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        preload: [nodes: ^nodes_query, connections: []],
        order_by: [asc: f.position, asc: f.name]
      )

    query
    |> maybe_filter_ids(opts.flow_ids, :id)
    |> Repo.all()
  end

  defp maybe_load(:scenes, _project_id, %{include_scenes: false}), do: []

  defp maybe_load(:scenes, project_id, opts) do
    query =
      from(s in Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        preload: [:layers, :pins, :zones, :connections, :annotations],
        order_by: [asc: s.position, asc: s.name]
      )

    query
    |> maybe_filter_ids(opts.scene_ids, :id)
    |> Repo.all()
  end

  defp maybe_load(:screenplays, _project_id, %{include_screenplays: false}), do: []

  defp maybe_load(:screenplays, project_id, _opts) do
    elements_query = from(e in ScreenplayElement, order_by: [asc: e.position])

    from(sp in Screenplay,
      where: sp.project_id == ^project_id and is_nil(sp.deleted_at),
      preload: [elements: ^elements_query],
      order_by: [asc: sp.position, asc: sp.name]
    )
    |> Repo.all()
  end

  defp maybe_load(:localization, _project_id, %{include_localization: false}),
    do: %{languages: [], strings: [], glossary: []}

  defp maybe_load(:localization, project_id, opts) do
    languages = load_languages(project_id)

    locale_codes =
      case opts.languages do
        :all -> Enum.map(languages, & &1.locale_code)
        codes -> codes
      end

    %{
      languages: languages,
      strings: load_localized_texts(project_id, locale_codes),
      glossary: load_glossary(project_id)
    }
  end

  defp maybe_load(:assets, _project_id, %{include_assets: false}), do: []

  defp maybe_load(:assets, project_id, _opts) do
    from(a in Asset,
      where: a.project_id == ^project_id,
      order_by: [asc: a.inserted_at]
    )
    |> Repo.all()
  end

  # -- Helpers --

  defp blocks_preload_query do
    from(b in Block,
      where: is_nil(b.deleted_at),
      preload: [:table_columns, :table_rows],
      order_by: [asc: b.position]
    )
  end

  defp load_languages(project_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id,
      order_by: [asc: l.position]
    )
    |> Repo.all()
  end

  defp load_localized_texts(project_id, locale_codes) do
    from(lt in LocalizedText,
      where: lt.project_id == ^project_id and lt.locale_code in ^locale_codes,
      order_by: [
        asc: lt.source_type,
        asc: lt.source_id,
        asc: lt.source_field,
        asc: lt.locale_code
      ]
    )
    |> Repo.all()
  end

  defp load_glossary(project_id) do
    from(g in GlossaryEntry,
      where: g.project_id == ^project_id,
      order_by: [asc: g.source_term, asc: g.target_locale]
    )
    |> Repo.all()
  end

  defp maybe_filter_ids(query, :all, _field), do: query

  defp maybe_filter_ids(query, ids, field) when is_list(ids) do
    from(q in query, where: field(q, ^field) in ^ids)
  end

  # -- Counters --

  defp count_if(:sheets, _project_id, %{include_sheets: false}), do: 0
  defp count_if(:flows, _project_id, %{include_flows: false}), do: 0
  defp count_if(:scenes, _project_id, %{include_scenes: false}), do: 0
  defp count_if(:screenplays, _project_id, %{include_screenplays: false}), do: 0

  defp count_if(:sheets, project_id, _opts) do
    from(s in Sheet, where: s.project_id == ^project_id and is_nil(s.deleted_at))
    |> Repo.aggregate(:count)
  end

  defp count_if(:flows, project_id, _opts) do
    from(f in Flow, where: f.project_id == ^project_id and is_nil(f.deleted_at))
    |> Repo.aggregate(:count)
  end

  defp count_if(:scenes, project_id, _opts) do
    from(s in Scene, where: s.project_id == ^project_id and is_nil(s.deleted_at))
    |> Repo.aggregate(:count)
  end

  defp count_if(:screenplays, project_id, _opts) do
    from(sp in Screenplay, where: sp.project_id == ^project_id and is_nil(sp.deleted_at))
    |> Repo.aggregate(:count)
  end

  defp count_if(:assets, project_id, _opts) do
    from(a in Asset, where: a.project_id == ^project_id) |> Repo.aggregate(:count)
  end

  defp count_nodes(project_id, _opts) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at)
    )
    |> Repo.aggregate(:count)
  end
end
