defmodule Storyarn.Sheets.Health do
  @moduledoc """
  Public capability boundary for Sheet health and dashboard projections.

  The same pure rules and enriched snapshot shape drive both the open editor
  and project-wide health surfaces so callers cannot accidentally implement a
  second definition of Sheet health.
  """

  alias Storyarn.Sheets.Health.Contracts.Severity
  alias Storyarn.Sheets.Health.Queries.Snapshots
  alias Storyarn.Sheets.Health.Queries.Stats
  alias Storyarn.Sheets.Health.Rules.Checker

  defdelegate sheet_stats_for_project(project_id), to: Stats
  defdelegate sheet_word_counts(project_id), to: Stats
  defdelegate referenced_block_ids_for_project(project_id), to: Stats
  defdelegate list_dashboard_health_findings(project_id, referenced_ids \\ nil), to: Stats

  defdelegate sheet_health_findings(material), to: Snapshots, as: :findings
  defdelegate sheet_health_snapshot(material), to: Snapshots, as: :snapshot
  defdelegate load_project(project_id, referenced_ids \\ nil), to: Snapshots
  defdelegate health_variable_types(project_id), to: Snapshots, as: :variable_types

  defdelegate severity_for(code), to: Checker
  defdelegate codes(), to: Checker
  defdelegate finding(code, attrs \\ %{}), to: Checker
  defdelegate check(snapshot), to: Checker
  defdelegate severity_rank(severity), to: Severity, as: :rank
end
