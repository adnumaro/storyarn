defmodule Storyarn.Projects.References.MaterializedFormulaBindingRewriter do
  @moduledoc """
  Rewrites persisted formula bindings after portable snapshot materialization.

  The portable rewrite policy is pure and lives in
  `PortableVariableSnapshot`; this command owns the ordered, locked database
  update required after Sheet ids and namespaces have been materialized.
  """

  import Ecto.Query

  alias Storyarn.Projects.References.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.References.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.References.Persistence.TableColumnRecord, as: TableColumn
  alias Storyarn.Projects.References.Persistence.TableRowRecord, as: TableRow
  alias Storyarn.Projects.References.PortableVariableSnapshot
  alias Storyarn.Repo

  @spec rewrite(pos_integer(), PortableVariableSnapshot.portable_project_snapshot_plan(), map()) ::
          :ok | {:error, term()}
  def rewrite(project_id, plan, sheet_id_map)
      when is_integer(project_id) and project_id > 0 and is_map(plan) and is_map(sheet_id_map) do
    with :ok <- require_transaction(),
         {:ok, rewrites} <- PortableVariableSnapshot.variable_rewrites(plan, sheet_id_map),
         {:ok, formula_columns} <- materialized_formula_columns(project_id) do
      rewrite_materialized_formula_rows(project_id, formula_columns, rewrites.qualified)
    end
  end

  def rewrite(project_id, plan, sheet_id_map),
    do: {:error, {:invalid_materialized_formula_rewrite, project_id, plan, sheet_id_map}}

  defp require_transaction do
    if Repo.in_transaction?(),
      do: :ok,
      else: {:error, :materialized_formula_binding_rewrite_requires_transaction}
  end

  defp materialized_formula_columns(project_id) do
    columns =
      Repo.all(
        from(column in TableColumn,
          join: block in Block,
          on: block.id == column.block_id,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and block.type == "table" and
              column.type == "formula",
          select: {column.block_id, column.slug}
        )
      )

    {:ok,
     Enum.reduce(columns, %{}, fn {block_id, slug}, acc ->
       Map.update(acc, block_id, MapSet.new([slug]), &MapSet.put(&1, slug))
     end)}
  end

  defp rewrite_materialized_formula_rows(_project_id, formula_columns, _qualified_rewrites)
       when map_size(formula_columns) == 0, do: :ok

  defp rewrite_materialized_formula_rows(project_id, formula_columns, qualified_rewrites) do
    block_ids = Map.keys(formula_columns)

    rows =
      Repo.all(
        from(row in TableRow,
          join: block in Block,
          on: block.id == row.block_id,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and row.block_id in ^block_ids,
          order_by: [asc: row.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.reduce_while(rows, :ok, fn row, :ok ->
      formula_slugs = Map.fetch!(formula_columns, row.block_id)

      cells =
        PortableVariableSnapshot.rewrite_formula_row(
          %{"cells" => row.cells},
          formula_slugs,
          qualified_rewrites
        )["cells"]

      rewrite_materialized_formula_row(row, cells)
    end)
  end

  defp rewrite_materialized_formula_row(row, cells) when cells == row.cells, do: {:cont, :ok}

  defp rewrite_materialized_formula_row(row, cells) do
    case row
         |> Ecto.Changeset.change(cells: cells)
         |> Repo.update(stale_error_field: :cells, stale_error_message: "was concurrently modified") do
      {:ok, _row} ->
        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, {:materialized_formula_binding_rewrite_failed, row.id, reason}}}
    end
  end
end
