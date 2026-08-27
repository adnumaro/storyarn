defmodule Storyarn.Sheets.Expressions.Execution.FormulaResolverTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Sheets
  alias Storyarn.Sheets.Expressions.Execution.FormulaResolver

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})
    sheet = sheet_fixture(project, %{name: "Test Sheet"})
    block = table_block_fixture(sheet)

    # Create a number column named "Value"
    value_col = table_column_fixture(block, %{name: "Value", type: "number"})

    # Create a formula column (formula lives in cells, not column config)
    formula_col = table_column_fixture(block, %{name: "Modifier", type: "formula"})

    # The formula object stored in each cell
    formula_value = %{
      "expression" => "a - 3",
      "bindings" => %{
        "a" => %{"type" => "same_row", "column_slug" => value_col.slug}
      }
    }

    # Create rows with values
    row1 = table_row_fixture(block, %{name: "Row 1"})
    row2 = table_row_fixture(block, %{name: "Row 2"})

    # Set number cell values and formula cell values
    {:ok, row1} = Sheets.update_table_cell(row1, value_col.slug, "5")
    {:ok, row1} = Sheets.update_table_cell(row1, formula_col.slug, formula_value)
    {:ok, row2} = Sheets.update_table_cell(row2, value_col.slug, "7")
    {:ok, row2} = Sheets.update_table_cell(row2, formula_col.slug, formula_value)

    columns = Sheets.list_table_columns(block.id)
    rows = Sheets.list_table_rows(block.id)

    %{
      project: project,
      block: block,
      value_col: value_col,
      formula_col: formula_col,
      row1: row1,
      row2: row2,
      columns: columns,
      rows: rows
    }
  end

  describe "enrich_table_data/2" do
    test "computes same-row formula for all rows", ctx do
      enriched = enrich(ctx, ctx.columns, ctx.rows)

      # a - 3 where a = 5 → 2.0
      assert formula_cell(enriched, ctx, ctx.row1.id)["__result"] == 2.0

      # a - 3 where a = 7 → 4.0
      assert formula_cell(enriched, ctx, ctx.row2.id)["__result"] == 4.0
    end

    test "leaves the rows untouched when there are no formula columns", ctx do
      non_formula_cols = Enum.filter(ctx.columns, &(&1.type != "formula"))

      enriched = enrich(ctx, non_formula_cols, ctx.rows)

      assert enriched[ctx.block.id].rows == ctx.rows
      refute Map.has_key?(formula_cell(enriched, ctx, ctx.row1.id), "__result")
    end

    test "nil cell value defaults to 0", ctx do
      # Create a row with formula but without setting the value cell
      formula_value = %{
        "expression" => "a - 3",
        "bindings" => %{
          "a" => %{"type" => "same_row", "column_slug" => ctx.value_col.slug}
        }
      }

      row3 = table_row_fixture(ctx.block, %{name: "Row 3"})
      {:ok, _} = Sheets.update_table_cell(row3, ctx.formula_col.slug, formula_value)
      rows = Sheets.list_table_rows(ctx.block.id)

      enriched = enrich(ctx, ctx.columns, rows)

      # a - 3 where a = 0 (nil default) → -3.0
      assert formula_cell(enriched, ctx, row3.id)["__result"] == -3.0
    end

    test "invalid expression returns nil", ctx do
      # Update formula cell with invalid expression
      {:ok, _row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "(invalid",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      enriched = enrich(ctx, ctx.columns, rows)

      assert formula_cell(enriched, ctx, ctx.row1.id)["__result"] == nil
    end

    test "missing binding returns nil", ctx do
      # Update formula cell with unbound symbol
      {:ok, _row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "x + 1",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      enriched = enrich(ctx, ctx.columns, rows)

      assert formula_cell(enriched, ctx, ctx.row1.id)["__result"] == nil
    end

    test "empty expression returns nil", ctx do
      {:ok, _row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      enriched = enrich(ctx, ctx.columns, rows)

      assert formula_cell(enriched, ctx, ctx.row1.id)["__result"] == nil
    end

    test "preserves a non-map bindings value for health while skipping evaluation", ctx do
      table_data = %{
        ctx.block.id => %{
          columns: [%{slug: ctx.formula_col.slug, type: "formula"}],
          rows: [
            %{
              id: ctx.row1.id,
              cells: %{
                ctx.formula_col.slug => %{
                  "expression" => "a + 1",
                  "bindings" => []
                }
              }
            }
          ]
        }
      }

      enriched = FormulaResolver.enrich_table_data(table_data, ctx.project.id)
      cell = enriched[ctx.block.id].rows |> hd() |> then(& &1.cells[ctx.formula_col.slug])

      assert cell["bindings"] == []
      assert cell["__resolved"] == %{}
      assert cell["__result"] == nil
    end

    test "ignores a variable binding without a binary ref instead of resolving it", ctx do
      table_data = %{
        ctx.block.id => %{
          columns: [%{slug: ctx.formula_col.slug, type: "formula"}],
          rows: [
            %{
              id: ctx.row1.id,
              cells: %{
                ctx.formula_col.slug => %{
                  "expression" => "a + 1",
                  "bindings" => %{"a" => %{"type" => "variable"}}
                }
              }
            }
          ]
        }
      }

      enriched = FormulaResolver.enrich_table_data(table_data, ctx.project.id)
      cell = enriched[ctx.block.id].rows |> hd() |> then(& &1.cells[ctx.formula_col.slug])

      assert cell["bindings"] == %{"a" => %{"type" => "variable"}}
      assert cell["__resolved"] == %{}
      assert cell["__result"] == nil
    end
  end

  # Wraps a single block's columns/rows in the batch shape
  # `Sheets.batch_load_table_data/1` returns, which is what the enricher takes.
  defp enrich(ctx, columns, rows) do
    FormulaResolver.enrich_table_data(
      %{ctx.block.id => %{columns: columns, rows: rows}},
      ctx.project.id
    )
  end

  defp formula_cell(enriched, ctx, row_id) do
    enriched[ctx.block.id].rows
    |> Enum.find(&(&1.id == row_id))
    |> Map.fetch!(:cells)
    |> Map.get(ctx.formula_col.slug)
  end
end
