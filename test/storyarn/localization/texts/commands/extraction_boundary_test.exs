defmodule Storyarn.Localization.Texts.Commands.ExtractionBoundaryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization

  test "sheet batch extraction rejects a mixed-project source set" do
    project = project_fixture(user_fixture())
    foreign_project = project_fixture(user_fixture())
    sheet = sheet_fixture(project)
    sibling_sheet = sheet_fixture(project)
    foreign_sheet = sheet_fixture(foreign_project)

    assert :ok = Localization.extract_sheet_blocks_for_sheets([sheet.id, sibling_sheet.id])

    assert {:error, :mixed_project_sheet_ids} =
             Localization.extract_sheet_blocks_for_sheets([sheet.id, foreign_sheet.id])

    assert {:error, :mixed_project_sheet_ids} =
             Localization.extract_sheet_blocks_for_sheets([foreign_sheet.id, sheet.id])

    assert {:error, :mixed_project_sheet_ids} =
             Localization.extract_sheet_blocks_for_sheets([-1, sheet.id, foreign_sheet.id])
  end
end
