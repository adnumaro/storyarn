defmodule Storyarn.Projects.SheetImportPersistenceTest do
  @moduledoc """
  Pins that the Project-owned import writer behaves exactly like the Sheet
  tool's retired import path, whose tests these are.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.SheetImportPersistence
  alias Storyarn.Sheets

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "list_shortcuts/1" do
    test "returns MapSet of all shortcuts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet B", shortcut: "b"})

      shortcuts = SheetImportPersistence.list_shortcuts(project.id)

      assert MapSet.member?(shortcuts, "a")
      assert MapSet.member?(shortcuts, "b")
    end

    test "excludes deleted sheet shortcuts" do
      %{project: project} = setup_project()

      {:ok, _active} = Sheets.create_sheet(project, %{name: "Active", shortcut: "active"})
      {:ok, deleted} = Sheets.create_sheet(project, %{name: "Deleted", shortcut: "deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      shortcuts = SheetImportPersistence.list_shortcuts(project.id)

      assert MapSet.member?(shortcuts, "active")
      refute MapSet.member?(shortcuts, "deleted")
    end

    test "returns empty MapSet for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetImportPersistence.list_shortcuts(project.id) == MapSet.new()
    end
  end

  describe "detect_shortcut_conflicts/2" do
    test "returns conflicting shortcuts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet B", shortcut: "b"})

      conflicts = SheetImportPersistence.detect_shortcut_conflicts(project.id, ["a", "c"])

      assert "a" in conflicts
      refute "c" in conflicts
    end

    test "returns empty list when no conflicts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})

      assert SheetImportPersistence.detect_shortcut_conflicts(project.id, ["x", "y"]) == []
    end

    test "returns empty list for empty input" do
      %{project: project} = setup_project()

      assert SheetImportPersistence.detect_shortcut_conflicts(project.id, []) == []
    end

    test "excludes soft-deleted sheet shortcuts" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Deleted", shortcut: "deleted"})
      {:ok, _} = Sheets.trash_sheet(sheet)

      conflicts = SheetImportPersistence.detect_shortcut_conflicts(project.id, ["deleted"])

      assert conflicts == []
    end
  end

  describe "list_active_variable_contracts/2" do
    test "loads regular and referenceable table-cell contracts" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Variables", shortcut: "variables"})
      _regular = block_fixture(sheet, %{type: "number", variable_name: "gold"})
      table = table_block_fixture(sheet, %{label: "Inventory"})
      damage = table_column_fixture(table, %{name: "Damage", type: "number"})
      hidden = table_column_fixture(table, %{name: "Hidden", type: "text", is_constant: true})
      formula = table_column_fixture(table, %{name: "Computed", type: "formula", is_constant: true})
      sword = table_row_fixture(table, %{name: "Sword"})

      contracts = SheetImportPersistence.list_active_variable_contracts(project.id, [sheet.shortcut])

      assert contracts[{sheet.shortcut, "gold"}] == "number"
      assert contracts[{:table, sheet.shortcut, table.variable_name}] == :present
      assert contracts[{:table_row, sheet.shortcut, table.variable_name, sword.slug}] == :present
      assert contracts[{:table_column, sheet.shortcut, table.variable_name, damage.slug}] == "number"
      assert contracts[{:table_column, sheet.shortcut, table.variable_name, formula.slug}] == "formula"
      refute Map.has_key?(contracts, {:table_column, sheet.shortcut, table.variable_name, hidden.slug})
    end

    test "does not load table cells from an inactive sheet" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Variables", shortcut: "variables"})
      table = table_block_fixture(sheet, %{label: "Inventory"})
      column = table_column_fixture(table, %{name: "Damage", type: "number"})
      row = table_row_fixture(table, %{name: "Sword"})
      {:ok, _sheet} = Sheets.trash_sheet(sheet)

      contracts = SheetImportPersistence.list_active_variable_contracts(project.id, [sheet.shortcut])

      refute Map.has_key?(contracts, {:table, sheet.shortcut, table.variable_name})
      refute Map.has_key?(contracts, {:table_row, sheet.shortcut, table.variable_name, row.slug})
      refute Map.has_key?(contracts, {:table_column, sheet.shortcut, table.variable_name, column.slug})
    end
  end

  describe "import_block/2" do
    setup do
      %{project: project} = setup_project()
      %{project: project, sheet: sheet_fixture(project)}
    end

    test "creates a block without side effects", %{sheet: sheet} do
      {:ok, block} =
        SheetImportPersistence.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Imported"},
          value: %{"content" => "Imported runtime words"},
          variable_name: "imported",
          position: 0
        })

      assert block.type == "text"
      assert block.config["label"] == "Imported"
      assert block.word_count == 3
    end

    test "does not auto-deduplicate variable names (relies on DB constraint)", %{sheet: sheet} do
      {:ok, _b1} =
        SheetImportPersistence.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 0
        })

      # import_block does NOT deduplicate in code, but the DB has a unique
      # constraint on (sheet_id, variable_name), so a duplicate raises
      assert_raise Ecto.ConstraintError, fn ->
        SheetImportPersistence.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 1
        })
      end
    end

    test "allows different variable names", %{sheet: sheet} do
      {:ok, b1} =
        SheetImportPersistence.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 0
        })

      {:ok, b2} =
        SheetImportPersistence.import_block(sheet.id, %{
          type: "number",
          config: %{"label" => "Age"},
          variable_name: "age",
          position: 1
        })

      assert b1.variable_name == "name"
      assert b2.variable_name == "age"
    end
  end
end
