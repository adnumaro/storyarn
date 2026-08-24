defmodule Storyarn.References.FormulaUsageReadModel do
  @moduledoc """
  Project-owned read of formula cells that bind one qualified variable reference.

  Mirrors the Sheet tool's formula-usage page exactly, including its limit
  bounds. Only formula-cell navigation metadata is selected — the expression,
  bindings object and evaluated cell value never cross this boundary.
  """

  import Ecto.Query, warn: false

  alias Storyarn.References.Persistence.BlockRecord
  alias Storyarn.References.Persistence.SheetRecord
  alias Storyarn.References.Persistence.TableColumnRecord
  alias Storyarn.References.Persistence.TableRowRecord
  alias Storyarn.Repo

  @default_limit 25
  @max_limit 50

  @spec list_formula_usages(integer(), String.t(), keyword()) :: %{items: [map()], truncated: boolean()}
  def list_formula_usages(project_id, qualified_ref, opts \\ [])

  def list_formula_usages(project_id, qualified_ref, opts) when is_binary(qualified_ref) do
    limit = bounded_limit(opts)

    items =
      Repo.all(
        from(row in TableRowRecord,
          join: block in BlockRecord,
          on: block.id == row.block_id,
          join: sheet in SheetRecord,
          on: sheet.id == block.sheet_id,
          join: column in TableColumnRecord,
          on: column.block_id == block.id and column.type == "formula",
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and
              block.type == "table",
          where:
            fragment(
              """
              jsonb_path_exists(
                COALESCE(? -> ? -> 'bindings', '{}'::jsonb),
                '$.* \\? (@.type == "variable" && @.ref == $reference)',
                jsonb_build_object('reference', to_jsonb(?::text))
              )
              """,
              row.cells,
              column.slug,
              ^qualified_ref
            ),
          order_by: [
            asc: sheet.name,
            asc: block.position,
            asc: row.position,
            asc: column.position,
            asc: row.id,
            asc: column.id
          ],
          limit: ^(limit + 1),
          select: %{
            sheet_id: sheet.id,
            sheet_name: sheet.name,
            sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block_id: block.id,
            table_name: block.variable_name,
            row_id: row.id,
            row_name: row.name,
            row_slug: row.slug,
            column_id: column.id,
            column_name: column.name,
            column_slug: column.slug
          }
        )
      )

    %{items: Enum.take(items, limit), truncated: length(items) > limit}
  end

  def list_formula_usages(_project_id, _qualified_ref, _opts), do: %{items: [], truncated: false}

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
