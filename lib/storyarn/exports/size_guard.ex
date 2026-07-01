defmodule Storyarn.Exports.SizeGuard do
  @moduledoc """
  Guards synchronous export paths from loading oversized projects into memory.

  The current serializers operate on fully materialized project data. Until the
  streaming serializer path is implemented, this guard rejects exports whose
  selected sections exceed conservative row-count limits before validation or
  collection starts loading large associations.
  """

  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions

  @default_limits %{
    sheets: 1_000,
    sheet_blocks: 50_000,
    table_columns: 50_000,
    table_rows: 100_000,
    flows: 500,
    nodes: 100_000,
    flow_connections: 150_000,
    scenes: 200,
    scene_layers: 2_000,
    scene_pins: 50_000,
    scene_zones: 50_000,
    scene_connections: 50_000,
    scene_annotations: 50_000,
    screenplays: 500,
    screenplay_elements: 100_000,
    assets: 5_000,
    languages: 50,
    localized_texts: 100_000,
    glossary_entries: 10_000,
    total_rows: 250_000
  }

  @doc """
  Returns the default synchronous export limits.
  """
  def default_limits, do: @default_limits

  @doc """
  Checks whether a project can be safely exported through the in-memory path.
  """
  def ensure_within_limit(project_id, %ExportOptions{} = opts) do
    counts = DataCollector.count_entities(project_id, opts)
    limits = configured_limits()

    violations =
      limits
      |> Enum.filter(fn {key, limit} -> limited?(Map.get(counts, key, 0), limit) end)
      |> Map.new(fn {key, limit} -> {key, %{count: Map.get(counts, key, 0), limit: limit}} end)

    if violations == %{} do
      :ok
    else
      {:error, {:export_too_large, %{counts: counts, limits: limits, violations: violations}}}
    end
  end

  defp configured_limits do
    configured =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:limits, %{})

    Map.merge(@default_limits, configured)
  end

  defp limited?(_count, nil), do: false
  defp limited?(count, limit) when is_integer(limit), do: count > limit
end
