defmodule Storyarn.Projects.References.MaterializedFormulaBindingRewriterTest do
  use Storyarn.DataCase, async: false

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.References.MaterializedFormulaBindingRewriter
  alias Storyarn.Repo
  alias Storyarn.Sheets

  test "reports a later row failure and lets the caller roll back earlier rewrites" do
    project = project_fixture()
    sheet = sheet_fixture(project, %{name: "Materialized formulas"})
    table = table_block_fixture(sheet, %{label: "Calculations"})
    formula = table_column_fixture(table, %{name: "Computed", type: "formula"})
    first_row = hd(table.table_rows)
    second_row = table_row_fixture(table)
    source_sheet_id = sheet.id + 1
    source_ref = "#{source_sheet_id}.hp"
    destination_ref = "#{sheet.id}.hp"
    original_cell = formula_cell(source_ref)

    first_row = persist_formula_cell(first_row, formula.slug, original_cell)
    second_row = persist_formula_cell(second_row, formula.slug, original_cell)
    plan = portable_rewrite_plan(source_sheet_id, source_ref)

    install_second_row_stale_trigger(first_row.id, second_row.id)

    assert {:error, {:materialized_formula_binding_rewrite_failed, failed_row_id, %Ecto.Changeset{} = changeset}} =
             Repo.transaction(fn ->
               case MaterializedFormulaBindingRewriter.rewrite(
                      project.id,
                      plan,
                      %{source_sheet_id => sheet.id}
                    ) do
                 :ok -> :ok
                 {:error, reason} -> Repo.rollback(reason)
               end
             end)

    assert failed_row_id == second_row.id
    assert errors_on(changeset).cells == ["was concurrently modified"]
    assert formula_ref(Repo.reload!(first_row), formula.slug) == source_ref
    assert formula_ref(Repo.reload!(second_row), formula.slug) == source_ref
    refute formula_ref(Repo.reload!(first_row), formula.slug) == destination_ref
  end

  defp persist_formula_cell(row, formula_slug, cell) do
    {:ok, row} = Sheets.update_table_cell(row, formula_slug, cell)
    row
  end

  defp formula_cell(ref) do
    %{
      "expression" => "hp",
      "bindings" => %{
        "hp" => %{"type" => "variable", "ref" => ref}
      }
    }
  end

  defp formula_ref(row, formula_slug) do
    row.cells[formula_slug]["bindings"]["hp"]["ref"]
  end

  defp portable_rewrite_plan(source_sheet_id, source_ref) do
    namespace = Integer.to_string(source_sheet_id)
    resolution_key = {:regular, namespace, "hp"}

    %{
      version: 1,
      sheet_ids: MapSet.new([source_sheet_id]),
      namespace_owners: %{namespace => source_sheet_id},
      rewritable_namespaces: %{namespace => source_sheet_id},
      qualified_targets: %{source_ref => resolution_key},
      rewritable_qualified_targets: %{source_ref => resolution_key}
    }
  end

  defp install_second_row_stale_trigger(first_row_id, second_row_id) do
    Repo.query!(
      "SELECT set_config('storyarn.test_first_formula_row_id', $1, true)",
      [to_string(first_row_id)]
    )

    Repo.query!(
      "SELECT set_config('storyarn.test_second_formula_row_id', $1, true)",
      [to_string(second_row_id)]
    )

    Repo.query!("""
    CREATE FUNCTION storyarn_test_stale_second_formula_row()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.id = current_setting('storyarn.test_first_formula_row_id')::bigint THEN
        DELETE FROM table_rows
        WHERE id = current_setting('storyarn.test_second_formula_row_id')::bigint;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER storyarn_test_stale_second_formula_row
    BEFORE UPDATE ON table_rows
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_test_stale_second_formula_row()
    """)
  end
end
