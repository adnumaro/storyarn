defmodule Storyarn.Scenes.Health do
  @moduledoc false

  alias Storyarn.Scenes.Health.Queries.Snapshots
  alias Storyarn.Scenes.Health.Queries.Stats
  alias Storyarn.Scenes.Health.Rules.Checker
  alias Storyarn.Scenes.Severity

  defdelegate scene_stats_for_project(project_id), to: Stats
  defdelegate scenes_with_background_count(project_id), to: Stats
  defdelegate list_dashboard_health_findings(project_id), to: Stats

  defdelegate references(attrs), to: Snapshots
  defdelegate findings(scene, collections, references), to: Snapshots
  defdelegate load_project(project_id), to: Snapshots

  defdelegate severity_for(code), to: Checker
  defdelegate codes(), to: Checker
  defdelegate entity_types(), to: Checker
  defdelegate finding(code, attrs \\ %{}), to: Checker
  defdelegate check(snapshot), to: Checker
  defdelegate severity_rank(severity), to: Severity, as: :rank
end
