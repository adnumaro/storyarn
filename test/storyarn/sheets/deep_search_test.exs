defmodule Storyarn.Sheets.DeepSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project, user: user}
  end

  describe "search_sheets_deep/3" do
    test "searches sheet name, shortcut, and description", %{project: project} do
      target =
        sheet_fixture(project, %{
          name: "Moonlit Archive",
          shortcut: "lore.private-codex",
          description: "Catalogued by the silver cartographer"
        })

      assert result_ids(Sheets.search_sheets_deep(project.id, "Moonlit")) == [target.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "private-codex")) == [target.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "silver cartographer")) == [target.id]
    end

    test "searches active block configuration and values without duplicating sheets", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Character Record"})

      block_fixture(sheet, %{
        config: %{"label" => "Cerulean oath", "placeholder" => "Enter oath"},
        value: %{"content" => "Promises beneath the glass moon"}
      })

      block_fixture(sheet, %{
        config: %{"label" => "Second cerulean oath"},
        value: %{"content" => "Another glass moon mention"}
      })

      block_fixture(sheet, %{
        type: "select",
        config: %{
          "label" => "Faction",
          "options" => [%{"key" => "umbral", "value" => "Umbral diplomat"}]
        }
      })

      assert result_ids(Sheets.search_sheets_deep(project.id, "cerulean oath")) == [sheet.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "glass moon")) == [sheet.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "Umbral diplomat")) == [sheet.id]
    end

    test "searches table column, row, and cell text", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Inventory"})
      table = table_block_fixture(sheet, %{label: "Equipment"})
      column = table_column_fixture(table, %{name: "Inscription Meridian", type: "text"})
      row = table_row_fixture(table, %{name: "Relic Atrium"})

      assert {:ok, _updated} =
               Sheets.update_table_cell(row, column.slug, "Forged in the amber observatory")

      assert result_ids(Sheets.search_sheets_deep(project.id, "Inscription Meridian")) == [sheet.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "Relic Atrium")) == [sheet.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "amber observatory")) == [sheet.id]
    end

    test "searches gallery labels and descriptions", %{project: project, user: user} do
      sheet = sheet_fixture(project, %{name: "Portraits"})
      gallery = block_fixture(sheet, %{type: "gallery", config: %{"label" => "Gallery"}})
      asset = image_asset_fixture(project, user)

      assert {:ok, image} = Sheets.add_gallery_image(gallery, asset.id)

      assert {:ok, _updated} =
               Sheets.update_gallery_image(image, %{
                 label: "Vermilion envoy",
                 description: "Standing at the northern lighthouse"
               })

      assert result_ids(Sheets.search_sheets_deep(project.id, "Vermilion envoy")) == [sheet.id]
      assert result_ids(Sheets.search_sheets_deep(project.id, "northern lighthouse")) == [sheet.id]
    end

    test "excludes other projects, trashed sheets, and content in deleted blocks", %{
      project: project
    } do
      other_project = project_fixture()
      other_sheet = sheet_fixture(other_project, %{name: "Foreign Sheet"})
      block_fixture(other_sheet, %{value: %{"content" => "scoped raven phrase"}})

      trashed_sheet = sheet_fixture(project, %{name: "Trashed Sheet"})
      block_fixture(trashed_sheet, %{value: %{"content" => "scoped raven phrase"}})
      assert {:ok, _trashed} = Sheets.trash_sheet(trashed_sheet)

      active_sheet = sheet_fixture(project, %{name: "Active Sheet"})
      deleted_block = block_fixture(active_sheet, %{value: %{"content" => "scoped raven phrase"}})
      assert {:ok, _deleted} = Sheets.delete_block(deleted_block)

      assert Sheets.search_sheets_deep(project.id, "scoped raven phrase") == []
    end

    test "treats LIKE wildcard characters as literal text", %{project: project} do
      literal = sheet_fixture(project, %{name: "100% Complete"})
      sheet_fixture(project, %{name: "1000 Complete"})

      assert result_ids(Sheets.search_sheets_deep(project.id, "%")) == [literal.id]
    end

    test "applies deterministic pagination and clamps negative bounds", %{project: project} do
      alpha = sheet_fixture(project, %{name: "Deep Alpha"})
      bravo = sheet_fixture(project, %{name: "Deep Bravo"})
      sheet_fixture(project, %{name: "Deep Charlie"})

      assert result_ids(Sheets.search_sheets_deep(project.id, "Deep", limit: 1, offset: 1)) == [
               bravo.id
             ]

      assert result_ids(Sheets.search_sheets_deep(project.id, "Deep", limit: 0, offset: -10)) == [
               alpha.id
             ]
    end
  end

  defp result_ids(results), do: Enum.map(results, & &1.id)
end
