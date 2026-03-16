defmodule Storyarn.Sheets.SheetStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Repo
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}

  @variable_types ~w(text rich_text number select multi_select boolean date)

  # ===========================================================================
  # Stats
  # ===========================================================================

  @variable_column_types ~w(number text boolean select multi_select date reference formula)

  @doc """
  Returns per-sheet block and variable counts for all sheets in a project.
  Includes both regular block variables and table cell variables (row × column).
  Returns `%{sheet_id => %{block_count, variable_count}}`.
  """
  def sheet_stats_for_project(project_id) do
    # Regular block counts + non-table variable counts
    base_stats =
      from(s in Sheet,
        left_join: b in Block,
        on: b.sheet_id == s.id and is_nil(b.deleted_at),
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        group_by: s.id,
        select:
          {s.id,
           %{
             block_count: count(b.id),
             variable_count:
               fragment(
                 "COUNT(CASE WHEN ? = ANY(?) AND ? = false THEN 1 END)",
                 b.type,
                 ^@variable_types,
                 b.is_constant
               )
           }}
      )
      |> Repo.all()
      |> Map.new()

    # Table cell variable counts: rows × variable columns per table block per sheet
    table_var_counts =
      from(tc in TableColumn,
        join: b in Block,
        on: tc.block_id == b.id,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        join: tr in TableRow,
        on: tr.block_id == b.id,
        where:
          s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at) and
            b.type == "table" and
            tc.type in ^@variable_column_types and
            (tc.is_constant == false or tc.type == "formula"),
        group_by: s.id,
        select: {s.id, count()}
      )
      |> Repo.all()
      |> Map.new()

    # Merge table variable counts into base stats
    Map.new(base_stats, fn {sheet_id, stats} ->
      table_vars = Map.get(table_var_counts, sheet_id, 0)
      {sheet_id, %{stats | variable_count: stats.variable_count + table_vars}}
    end)
  end

  @doc """
  Returns per-sheet word counts including:
  - Sheet names and descriptions
  - Text/rich_text block content words (from denormalized `word_count` column)
  - Block labels and placeholders
  - Select/multi_select option values
  - Table column and row names
  - Gallery image labels and descriptions

  Returns `%{sheet_id => word_count}`.
  """
  defdelegate sheet_word_counts(project_id), to: LocalizableWords

  @doc """
  Returns a MapSet of block IDs that have at least one variable reference.
  """
  def referenced_block_ids_for_project(project_id) do
    from(vr in VariableReference,
      join: b in Block,
      on: vr.block_id == b.id,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      distinct: vr.block_id,
      select: vr.block_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # ===========================================================================
  # Issue Detection
  # ===========================================================================

  @doc """
  Detects issues in sheets for a project.
  Returns `[%{issue_type, sheet_id, sheet_name, ...}]`.

  Issue types:
  - `:empty_sheet` — leaf sheet with 0 blocks
  - `:unused_variable` — variable block with no references (capped at 10)
  - `:missing_shortcut` — sheet with nil/empty shortcut
  """
  def detect_sheet_issues(project_id, referenced_ids \\ nil) do
    empty = detect_empty_sheets(project_id)
    unused = detect_unused_variables(project_id, referenced_ids)
    missing = detect_missing_shortcuts(project_id)
    empty ++ unused ++ missing
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp detect_empty_sheets(project_id) do
    # Sheets with no blocks AND no children are "empty"
    from(s in Sheet,
      left_join: b in Block,
      on: b.sheet_id == s.id and is_nil(b.deleted_at),
      left_join: child in Sheet,
      on:
        child.parent_id == s.id and child.project_id == ^project_id and is_nil(child.deleted_at),
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(child.id),
      group_by: [s.id, s.name],
      having: count(b.id) == 0,
      select: %{issue_type: :empty_sheet, sheet_id: s.id, sheet_name: s.name}
    )
    |> Repo.all()
  end

  defp detect_unused_variables(project_id, referenced_ids) do
    referenced_ids = referenced_ids || referenced_block_ids_for_project(project_id)

    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at) and
          b.type in ^@variable_types and b.is_constant == false,
      select: %{
        block_id: b.id,
        variable_name: b.variable_name,
        sheet_id: s.id,
        sheet_name: s.name,
        sheet_shortcut: s.shortcut
      }
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(referenced_ids, &1.block_id))
    |> Enum.take(10)
    |> Enum.map(fn row ->
      %{
        issue_type: :unused_variable,
        sheet_id: row.sheet_id,
        sheet_name: row.sheet_name,
        sheet_shortcut: row.sheet_shortcut,
        variable_name: row.variable_name
      }
    end)
  end

  defp detect_missing_shortcuts(project_id) do
    from(s in Sheet,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          (is_nil(s.shortcut) or s.shortcut == ""),
      select: %{issue_type: :missing_shortcut, sheet_id: s.id, sheet_name: s.name}
    )
    |> Repo.all()
  end
end
