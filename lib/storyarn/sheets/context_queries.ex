defmodule Storyarn.Sheets.ContextQueries do
  @moduledoc """
  Bounded sheet reads for deterministic AI context packages.

  The caller must authorize the project before invoking these helpers.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @spec get_sheet_brief(integer(), integer()) :: Sheet.t() | nil
  def get_sheet_brief(project_id, sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            is_nil(sheet.deleted_at)
      )
    )
  end

  @spec list_sheet_briefs(integer(), [integer()], pos_integer()) :: [Sheet.t()]
  def list_sheet_briefs(_project_id, [], _limit), do: []

  def list_sheet_briefs(project_id, sheet_ids, limit) do
    Repo.all(
      from(sheet in Sheet,
        where:
          sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
            is_nil(sheet.deleted_at),
        order_by: [asc: sheet.id],
        limit: ^limit
      )
    )
  end

  @spec list_blocks(integer(), integer(), [integer()], pos_integer()) :: [Block.t()]
  def list_blocks(_project_id, _sheet_id, [], _limit), do: []

  def list_blocks(project_id, sheet_id, block_ids, limit) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            block.id in ^block_ids and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
        order_by: [asc: block.position, asc: block.id],
        limit: ^limit
      )
    )
  end

  @spec list_blocks_by_labels(integer(), integer(), [String.t()], pos_integer()) :: [Block.t()]
  def list_blocks_by_labels(_project_id, _sheet_id, [], _limit), do: []

  def list_blocks_by_labels(project_id, sheet_id, labels, limit) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            fragment("?->>'label' = ANY(?)", block.config, ^labels) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
        order_by: [asc: block.position, asc: block.id],
        limit: ^limit
      )
    )
  end

  @spec count_blocks_by_labels(integer(), integer(), [String.t()]) :: non_neg_integer()
  def count_blocks_by_labels(_project_id, _sheet_id, []), do: 0

  def count_blocks_by_labels(project_id, sheet_id, labels) do
    Repo.aggregate(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            fragment("?->>'label' = ANY(?)", block.config, ^labels) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at)
      ),
      :count,
      :id
    )
  end
end
