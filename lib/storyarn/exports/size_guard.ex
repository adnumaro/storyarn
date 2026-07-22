defmodule Storyarn.Exports.SizeGuard do
  @moduledoc """
  Guards synchronous export paths from loading oversized projects into memory.

  The current serializers operate on fully materialized project data. Until the
  streaming serializer path is implemented, this guard rejects exports whose
  selected sections exceed conservative row-count or source-byte limits before
  validation or collection starts loading large associations.
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

  @default_max_sync_export_bytes 64 * 1024 * 1024
  @default_serialization_expansion_factor 8

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

    count_violations =
      limits
      |> Enum.filter(fn {key, limit} -> limited?(Map.get(counts, key, 0), limit) end)
      |> Map.new(fn {key, limit} -> {key, %{count: Map.get(counts, key, 0), limit: limit}} end)

    if count_violations == %{} do
      ensure_source_bytes_within_limit(project_id, opts, counts, limits)
    else
      export_too_large(counts, limits, count_violations)
    end
  end

  @doc """
  Returns the configured maximum size for synchronous export output.
  """
  def max_sync_export_bytes do
    Application.get_env(
      :storyarn,
      :max_sync_export_bytes,
      @default_max_sync_export_bytes
    )
  end

  defp ensure_source_bytes_within_limit(project_id, opts, counts, limits) do
    source_bytes = DataCollector.estimate_source_bytes(project_id, opts)
    expansion_factor = serialization_expansion_factor()
    estimated_output_bytes = source_bytes.total_bytes * expansion_factor
    max_bytes = max_sync_export_bytes()

    if estimated_output_bytes <= max_bytes do
      :ok
    else
      violations = %{
        source_bytes: %{
          bytes: source_bytes.total_bytes,
          estimated_output_bytes: estimated_output_bytes,
          expansion_factor: expansion_factor,
          limit: max_bytes
        }
      }

      export_too_large(counts, limits, violations, source_bytes)
    end
  end

  defp export_too_large(counts, limits, violations, source_bytes \\ nil) do
    details = %{counts: counts, limits: limits, violations: violations}
    details = if source_bytes, do: Map.put(details, :source_bytes, source_bytes), else: details

    {:error, {:export_too_large, details}}
  end

  defp configured_limits do
    configured =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:limits, %{})

    Map.merge(@default_limits, configured)
  end

  defp serialization_expansion_factor do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:serialization_expansion_factor, @default_serialization_expansion_factor)
  end

  defp limited?(_count, nil), do: false
  defp limited?(count, limit) when is_integer(limit), do: count > limit
end
