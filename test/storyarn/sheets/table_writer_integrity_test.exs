defmodule Storyarn.Sheets.TableWriterIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block

  setup do
    project = project_fixture()
    sheet = sheet_fixture(project)
    table = table_block_fixture(sheet)

    %{project: project, sheet: sheet, table: table}
  end

  test "column and row writers reject forged ownership and inactive table owners", %{
    table: table
  } do
    foreign_table = table_block_fixture(sheet_fixture(project_fixture()))
    [column] = Sheets.list_table_columns(table.id)
    [row] = Sheets.list_table_rows(table.id)

    assert {:error, :column_not_found} =
             column
             |> Map.put(:block_id, foreign_table.id)
             |> Sheets.update_table_column(%{name: "Forged"})

    assert {:error, :row_not_found} =
             row
             |> Map.put(:block_id, foreign_table.id)
             |> Sheets.update_table_row(%{name: "Forged"})

    assert Repo.reload!(column).name == column.name
    assert Repo.reload!(row).name == row.name

    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.update_all(
      from(block in Block, where: block.id == ^table.id),
      set: [deleted_at: deleted_at]
    )

    assert {:error, :inactive_table} =
             Sheets.create_table_column(table, %{name: "After trash", type: "text"})

    assert {:error, :inactive_table} =
             Sheets.update_table_column(column, %{name: "After trash"})

    assert {:error, :inactive_table} =
             Sheets.update_table_cell(row, column.slug, 10)
  end

  test "cell writers validate formula payloads and reject phantom or empty required columns atomically", %{
    table: table
  } do
    [base_column] = Sheets.list_table_columns(table.id)
    [row] = Sheets.list_table_rows(table.id)

    assert {:error, {:unknown_table_column, "phantom"}} =
             Sheets.update_table_cell(row, "phantom", "ghost")

    assert Repo.reload!(row).cells == %{"value" => nil}

    assert {:ok, formula_column} =
             Sheets.create_table_column(table, %{name: "Computed", type: "formula"})

    formula = %{
      "expression" => "a + 1",
      "bindings" => %{
        "a" => %{"type" => "same_row", "column_slug" => base_column.slug}
      }
    }

    assert {:ok, formula_row} =
             Sheets.update_table_cell(row, formula_column.slug, formula)

    assert formula_row.cells[formula_column.slug] == formula

    invalid_formula_values = [
      "1 + 1",
      %{"expression" => "1 + 1"},
      %{"expression" => "1 + 1", "bindings" => %{}, "__result" => 2},
      %{
        "expression" => "a + 1",
        "bindings" => %{
          "a" => %{"type" => "same_row", "column_slug" => "phantom"}
        }
      },
      %{
        "expression" => "a + 1",
        "bindings" => %{
          "forged" => %{"type" => "same_row", "column_slug" => base_column.slug}
        }
      }
    ]

    Enum.each(invalid_formula_values, fn invalid_formula ->
      assert {:error, {:invalid_formula_cell, "computed"}} =
               Sheets.update_table_cell(row, formula_column.slug, invalid_formula)

      assert Repo.reload!(row).cells[formula_column.slug] == formula
    end)

    assert {:ok, _required_column} =
             Sheets.update_table_column(base_column, %{required: true})

    assert {:error, {:required_table_column, "value"}} =
             Sheets.update_table_cell(row, "value", "")

    assert {:error, {:unknown_table_column, "phantom"}} =
             Sheets.update_table_cells(row, %{
               "value" => 42,
               "phantom" => "ghost"
             })

    persisted = Repo.reload!(row)
    assert persisted.cells["value"] == nil
    refute Map.has_key?(persisted.cells, "phantom")
  end

  test "row and column reorders require the exact unique scoped child set", %{
    table: table
  } do
    [first_column] = Sheets.list_table_columns(table.id)
    [first_row] = Sheets.list_table_rows(table.id)
    {:ok, second_column} = Sheets.create_table_column(table, %{name: "Second", type: "text"})
    {:ok, second_row} = Sheets.create_table_row(table, %{name: "Second"})

    foreign_table = table_block_fixture(sheet_fixture(project_fixture()))
    [foreign_column] = Sheets.list_table_columns(foreign_table.id)
    [foreign_row] = Sheets.list_table_rows(foreign_table.id)

    invalid_column_orders = [
      [first_column.id],
      [first_column.id, first_column.id],
      [first_column.id, foreign_column.id],
      [first_column.id, "invalid"]
    ]

    Enum.each(invalid_column_orders, fn ids ->
      assert {:error, {:invalid_table_column_reorder, ^ids}} =
               Sheets.reorder_table_columns(table.id, ids)

      assert Enum.map(Sheets.list_table_columns(table.id), &{&1.id, &1.position}) == [
               {first_column.id, 0},
               {second_column.id, 1}
             ]
    end)

    invalid_row_orders = [
      [first_row.id],
      [first_row.id, first_row.id],
      [first_row.id, foreign_row.id],
      [first_row.id, "invalid"]
    ]

    Enum.each(invalid_row_orders, fn ids ->
      assert {:error, {:invalid_table_row_reorder, ^ids}} =
               Sheets.reorder_table_rows(table.id, ids)

      assert Enum.map(Sheets.list_table_rows(table.id), &{&1.id, &1.position}) == [
               {first_row.id, 0},
               {second_row.id, 1}
             ]
    end)
  end

  test "snapshot undo preserves child IDs and rejects foreign row payloads atomically", %{
    table: table
  } do
    [row] = Sheets.list_table_rows(table.id)
    {:ok, column} = Sheets.create_table_column(table, %{name: "Notes", type: "text"})
    {:ok, _updated_row} = Sheets.update_table_cell(row, column.slug, "keep me")

    column_snapshot = %{
      id: column.id,
      block_id: table.id,
      name: column.name,
      slug: column.slug,
      type: column.type,
      position: column.position,
      is_constant: column.is_constant,
      required: column.required,
      config: column.config
    }

    assert {:ok, _deleted} = Sheets.delete_table_column(column)

    foreign_table = table_block_fixture(sheet_fixture(project_fixture()))
    [foreign_row] = Sheets.list_table_rows(foreign_table.id)

    assert {:error, :invalid_table_snapshot} =
             Sheets.create_table_column_from_snapshot(
               table.id,
               column_snapshot,
               [{row.id, "keep me"}, {foreign_row.id, "steal"}]
             )

    refute Enum.any?(Sheets.list_table_columns(table.id), &(&1.id == column.id))

    assert {:ok, restored_column} =
             Sheets.create_table_column_from_snapshot(
               table.id,
               column_snapshot,
               [{row.id, "keep me"}]
             )

    assert restored_column.id == column.id
    assert Repo.reload!(row).cells[column.slug] == "keep me"

    {:ok, extra_row} = Sheets.create_table_row(table, %{name: "Restorable"})

    row_snapshot = %{
      id: extra_row.id,
      block_id: table.id,
      name: extra_row.name,
      slug: extra_row.slug,
      position: extra_row.position,
      cells: extra_row.cells
    }

    assert {:ok, _deleted_row} = Sheets.delete_table_row(extra_row)

    assert {:ok, restored_row} =
             Sheets.create_table_row_from_snapshot(
               table.id,
               row_snapshot,
               row_snapshot.cells
             )

    assert restored_row.id == extra_row.id
  end
end
