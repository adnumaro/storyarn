defmodule Storyarn.Sheets.AI do
  @moduledoc """
  Public capability boundary for Sheet-specific AI context construction.

  Provider policy and execution belong to `Storyarn.AI`; this capability owns
  only the Sheet vocabulary, bounded reads and source locks needed to construct
  deterministic context packages.
  """

  alias Storyarn.Sheets.AI.Queries.Context
  alias Storyarn.Sheets.AI.SheetContext
  alias Storyarn.Sheets.AI.SourceLocks

  defdelegate get_context_sheet(project_id, sheet_id),
    to: Context,
    as: :get_sheet_brief

  defdelegate list_context_sheets(project_id, sheet_ids, limit),
    to: Context,
    as: :list_sheet_briefs

  defdelegate list_context_blocks(project_id, sheet_id, block_ids, limit),
    to: Context,
    as: :list_blocks

  defdelegate list_context_blocks_by_labels(project_id, sheet_id, labels, limit),
    to: Context,
    as: :list_blocks_by_labels

  defdelegate count_context_blocks_by_labels(project_id, sheet_id, labels),
    to: Context,
    as: :count_blocks_by_labels

  defdelegate build_context(project, subject_ref, policy, entity_builder),
    to: SheetContext,
    as: :build

  defdelegate acquire_source_locks(task), to: SourceLocks, as: :acquire
end
