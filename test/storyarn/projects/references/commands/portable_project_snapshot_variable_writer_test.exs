defmodule Storyarn.Projects.References.PortableProjectSnapshotVariableWriterTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.References.PortableVariableSnapshot
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Sheets

  test "accepts writer-produced formulas with unbound symbols and invalid expressions" do
    project = project_fixture()
    sheet = sheet_fixture(project, %{name: "Formula source"})
    table = table_block_fixture(sheet, %{label: "Calculations"})
    formula = table_column_fixture(table, %{name: "Computed", type: "formula"})
    row = hd(table.table_rows)

    for cell <- [
          %{"expression" => "orphan * 2", "bindings" => %{}},
          %{"expression" => "1 +", "bindings" => %{}}
        ] do
      assert {:ok, _row} = Sheets.update_table_cell(row, formula.slug, cell)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      assert captured_formula_cell(snapshot, sheet.id, table.id, row.id, formula.slug) == cell
      assert {:ok, _plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
    end
  end

  defp captured_formula_cell(snapshot, sheet_id, table_id, row_id, column_slug) do
    sheet = Enum.find(snapshot["sheets"], &(&1["id"] == sheet_id))
    block = Enum.find(sheet["snapshot"]["blocks"], &(&1["original_id"] == table_id))
    row = Enum.find(block["table_data"]["rows"], &(&1["original_id"] == row_id))
    row["cells"][column_slug]
  end
end
