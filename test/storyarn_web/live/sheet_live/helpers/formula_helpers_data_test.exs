defmodule StoryarnWeb.SheetLive.Helpers.FormulaHelpersDataTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.SheetLive.Helpers.FormulaHelpers

  describe "search_binding_variables/3" do
    test "returns paged number and formula-compatible variables grouped by sheet shortcut" do
      project = Repo.preload(project_fixture(), :workspace)
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      _number_block =
        block_fixture(sheet, %{
          type: "number",
          variable_name: "health",
          config: %{"label" => "Health"},
          value: %{"value" => 10}
        })

      _text_block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "biography",
          config: %{"label" => "Biography"},
          value: %{"content" => "ignored"}
        })

      assert {[%{heading: "hero", items: [%{value: "hero.health", label: "health"}]}], false} =
               FormulaHelpers.search_binding_variables(project.id, "hero.health", 0)
    end
  end
end
