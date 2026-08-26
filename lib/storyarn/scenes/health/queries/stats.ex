defmodule Storyarn.Scenes.Health.Queries.Stats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.Health.Queries.Snapshots
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  # ===========================================================================
  # Stats
  # ===========================================================================

  @doc """
  Returns per-scene zone, pin, and connection counts in a single query.
  Returns `%{scene_id => %{zone_count, pin_count, connection_count}}`.
  """
  def scene_stats_for_project(project_id) do
    from(s in Scene,
      left_join: z in SceneZone,
      on: z.scene_id == s.id,
      left_join: p in ScenePin,
      on: p.scene_id == s.id,
      left_join: c in SceneConnection,
      on: c.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: s.id,
      select:
        {s.id,
         %{
           zone_count: count(z.id, :distinct),
           pin_count: count(p.id, :distinct),
           connection_count: count(c.id, :distinct)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the count of scenes that have a background image.
  Returns an integer.
  """
  def scenes_with_background_count(project_id) do
    Repo.one(
      from(s in Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and not is_nil(s.background_asset_id),
        select: count(s.id)
      )
    )
  end

  # ===========================================================================
  # Dashboard Health Overview
  # ===========================================================================

  @doc """
  Project-wide scene health findings for the dashboard.

  Runs the SAME `HealthChecker` the editor runs, over every scene of the
  project, so the dashboard can emit every one of `HealthChecker.codes/0`. It
  replaced nine hand-written aggregate detectors that re-implemented a quarter
  of the vocabulary in SQL and silently discriminated against the rest, so
  counts go UP: that is the correction, not a regression.

  Cost is a fixed number of queries for the whole project regardless of scene
  count (`HealthSnapshots.load_project/1`), then pure CPU per scene. The
  dashboard caches the result for 30s.
  """
  def list_dashboard_health_findings(project_id) do
    project_id
    |> Snapshots.load_project()
    |> Enum.flat_map(fn entry ->
      entry.scene
      |> Snapshots.findings(entry.collections, entry.references)
      |> Enum.map(&describe(&1, entry))
    end)
  end

  # The scene name and the offending element's own name ride in `details` so a
  # project-wide list can say WHICH pin of WHICH scene without a second query.
  # `sheet_stats.ex` does the same with `sheet_name`, `flow_stats.ex` with
  # `flow_name`.
  defp describe(finding, entry) do
    details =
      finding.details
      |> Map.put(:scene_name, entry.scene.name)
      |> put_entity_label(entry.labels, finding)

    %{finding | details: details}
  end

  defp put_entity_label(details, labels, finding) do
    case Map.get(labels, {finding.entity_type, finding.entity_id}) do
      nil -> details
      label -> Map.put(details, :entity_label, label)
    end
  end
end
