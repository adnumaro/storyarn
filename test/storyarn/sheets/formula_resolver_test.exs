defmodule Storyarn.Sheets.FormulaResolverTest do
  use Storyarn.DataCase

  alias Storyarn.Sheets
  alias Storyarn.Sheets.FormulaResolver

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

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

  describe "compute_all/3" do
    test "computes same-row formula for all rows", ctx do
      result = FormulaResolver.compute_all(ctx.columns, ctx.rows, ctx.project.id)

      # a - 3 where a = 5 → 2.0
      assert Map.get(result, ctx.row1.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               2.0

      # a - 3 where a = 7 → 4.0
      assert Map.get(result, ctx.row2.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               4.0
    end

    test "returns empty map when no formula columns", ctx do
      non_formula_cols = Enum.filter(ctx.columns, &(&1.type != "formula"))
      result = FormulaResolver.compute_all(non_formula_cols, ctx.rows, ctx.project.id)
      assert result == %{}
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

      result = FormulaResolver.compute_all(ctx.columns, rows, ctx.project.id)
      # a - 3 where a = 0 (nil default) → -3.0
      assert Map.get(result, row3.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               -3.0
    end

    test "invalid expression returns nil", ctx do
      # Update formula cell with invalid expression
      {:ok, row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "(invalid",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      result = FormulaResolver.compute_all(ctx.columns, rows, ctx.project.id)

      assert Map.get(result, ctx.row1.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               nil
    end

    test "missing binding returns nil", ctx do
      # Update formula cell with unbound symbol
      {:ok, row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "x + 1",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      result = FormulaResolver.compute_all(ctx.columns, rows, ctx.project.id)

      assert Map.get(result, ctx.row1.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               nil
    end

    test "empty expression returns nil", ctx do
      {:ok, row1} =
        Sheets.update_table_cell(ctx.row1, ctx.formula_col.slug, %{
          "expression" => "",
          "bindings" => %{}
        })

      rows = Sheets.list_table_rows(ctx.block.id)
      result = FormulaResolver.compute_all(ctx.columns, rows, ctx.project.id)

      assert Map.get(result, ctx.row1.id) |> Map.get(ctx.formula_col.slug) |> Map.get(:result) ==
               nil
    end
  end
end
