defmodule Storyarn.Exports.DataCollector do
  @moduledoc """
  Loads project data for export.

  Provides two modes:
  - `collect/2` — In-memory mode for small projects, validation, and tests
  - `count_entities/2` — Entity counting for progress estimation

  Streaming mode (`stream/2`) will be added in Phase E for large project support.
  """

  alias Storyarn.Assets
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Screenplays
  alias Storyarn.Sheets

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

  defp count_if(:sheets, project_id, _opts), do: Sheets.count_sheets(project_id)
  defp count_if(:flows, project_id, _opts), do: Flows.count_flows(project_id)
  defp count_if(:scenes, project_id, _opts), do: Scenes.count_scenes(project_id)
  defp count_if(:screenplays, project_id, _opts), do: Screenplays.count_screenplays(project_id)
  defp count_if(:assets, project_id, _opts), do: Assets.count_assets(project_id)

  defp count_nodes(project_id, _opts), do: Flows.count_nodes_for_project(project_id)
end
