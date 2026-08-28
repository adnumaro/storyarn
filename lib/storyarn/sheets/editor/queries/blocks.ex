defmodule Storyarn.Sheets.Editor.Queries.Blocks do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  def list(sheet_id) do
    Repo.all(
      from(block in Block,
        where: block.sheet_id == ^sheet_id and is_nil(block.deleted_at),
        order_by: [asc: block.position],
        preload: [:inherited_from_block]
      )
    )
  end

  def get(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([block], is_nil(block.deleted_at))
    |> Repo.one()
  end

  def get!(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([block], is_nil(block.deleted_at))
    |> Repo.one!()
  end

  def get_in_project(block_id, project_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: block.sheet_id == sheet.id,
        where: block.id == ^block_id and sheet.project_id == ^project_id,
        where: is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
        select: block
      )
    )
  end

  def get_in_project!(block_id, project_id) do
    case get_in_project(block_id, project_id) do
      nil -> raise Ecto.NoResultsError, queryable: Block
      block -> block
    end
  end

  def next_position(sheet_id) do
    query =
      from(block in Block,
        where: block.sheet_id == ^sheet_id and is_nil(block.deleted_at),
        select: max(block.position)
      )

    (Repo.one(query) || -1) + 1
  end

  def list_variable_names(sheet_id, exclude_block_id \\ nil) do
    query =
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and is_nil(block.deleted_at) and
            not is_nil(block.variable_name),
        select: block.variable_name
      )

    query =
      if exclude_block_id do
        where(query, [block], block.id != ^exclude_block_id)
      else
        query
      end

    Repo.all(query)
  end
end
