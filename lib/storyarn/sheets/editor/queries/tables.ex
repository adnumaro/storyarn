defmodule Storyarn.Sheets.Editor.Queries.Tables do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  def list_columns(block_id) do
    Repo.all(
      from(column in TableColumn,
        where: column.block_id == ^block_id,
        order_by: [asc: column.position]
      )
    )
  end

  def get_column!(block_id, column_id) do
    Repo.one!(
      from(column in TableColumn,
        where: column.id == ^column_id and column.block_id == ^block_id
      )
    )
  end

  def get_column(block_id, column_id) do
    Repo.one(
      from(column in TableColumn,
        where: column.id == ^column_id and column.block_id == ^block_id
      )
    )
  end

  def batch_load(block_ids) do
    columns =
      Repo.all(
        from(column in TableColumn,
          where: column.block_id in ^block_ids,
          order_by: [asc: column.block_id, asc: column.position, asc: column.id]
        )
      )

    rows =
      Repo.all(
        from(row in TableRow,
          where: row.block_id in ^block_ids,
          order_by: [asc: row.block_id, asc: row.position, asc: row.id]
        )
      )

    columns_by_block = Enum.group_by(columns, & &1.block_id)
    rows_by_block = Enum.group_by(rows, & &1.block_id)

    Map.new(block_ids, fn block_id ->
      {block_id,
       %{
         columns: Map.get(columns_by_block, block_id, []),
         rows: Map.get(rows_by_block, block_id, [])
       }}
    end)
  end

  def list_rows(block_id) do
    Repo.all(
      from(row in TableRow,
        where: row.block_id == ^block_id,
        order_by: [asc: row.position]
      )
    )
  end

  def get_row!(row_id), do: Repo.get!(TableRow, row_id)
  def get_row(row_id), do: Repo.get(TableRow, row_id)
end
