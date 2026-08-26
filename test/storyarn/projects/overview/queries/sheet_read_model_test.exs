defmodule Storyarn.Projects.SheetReadModelTest do
  @moduledoc """
  Pins that the Project-owned export reads behave exactly like the Sheet
  tool's retired export queries, whose tests these are.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.SheetReadModel
  alias Storyarn.Sheets

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "list_sheets_for_export/2" do
    test "returns sheets with blocks and table data preloaded" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      block_fixture(sheet, %{type: "text"})

      [result] = SheetReadModel.list_for_export(project.id)

      assert result.name == "Test Sheet"
      assert length(result.blocks) == 1
    end

    test "filters by specific sheet IDs when provided" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project, %{name: "Include"})
      _sheet2 = sheet_fixture(project, %{name: "Exclude"})

      results = SheetReadModel.list_for_export(project.id, filter_ids: [sheet1.id])

      assert length(results) == 1
      assert hd(results).name == "Include"
    end

    test "returns all sheets when filter_ids is :all" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Sheet A"})
      sheet_fixture(project, %{name: "Sheet B"})

      results = SheetReadModel.list_for_export(project.id, filter_ids: :all)

      assert length(results) == 2
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project, %{name: "Active"})
      deleted = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      results = SheetReadModel.list_for_export(project.id)

      assert length(results) == 1
      assert hd(results).name == "Active"
    end

    test "excludes soft-deleted blocks from preloaded data" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "Test"})
      _active_block = block_fixture(sheet, %{type: "text"})
      deleted_block = block_fixture(sheet, %{type: "number"})
      {:ok, _} = Sheets.delete_block(deleted_block)

      [result] = SheetReadModel.list_for_export(project.id)

      assert length(result.blocks) == 1
    end
  end

  describe "count_active/1" do
    test "returns count of non-deleted sheets" do
      %{project: project} = setup_project()

      sheet_fixture(project)
      sheet_fixture(project)
      deleted = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(deleted)

      assert SheetReadModel.count_active(project.id) == 2
    end

    test "returns 0 for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetReadModel.count_active(project.id) == 0
    end
  end
end
