defmodule Storyarn.Sheets.SheetStatsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.HealthChecker
  alias Storyarn.Sheets.SheetStats

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project, user: user}
  end

  describe "sheet_stats_for_project/1" do
    test "returns correct block and variable counts per sheet", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Stats Sheet"})
      # text block (variable)
      block_fixture(sheet, %{type: "text", is_constant: false})
      # number block (variable)
      block_fixture(sheet, %{type: "number", is_constant: false})
      # text block marked as constant
      block_fixture(sheet, %{type: "text", is_constant: true})

      stats = SheetStats.sheet_stats_for_project(project.id)

      assert Map.has_key?(stats, sheet.id)
      sheet_stats = stats[sheet.id]
      assert sheet_stats.block_count == 3
      assert sheet_stats.variable_count == 2
    end

    test "includes all sheets (parents and leaves)", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent Folder"})
      child = child_sheet_fixture(project, parent, %{name: "Child Leaf"})

      block_fixture(parent, %{type: "text"})
      block_fixture(child, %{type: "text"})

      stats = SheetStats.sheet_stats_for_project(project.id)

      assert Map.has_key?(stats, parent.id)
      assert Map.has_key?(stats, child.id)
      assert stats[parent.id].block_count == 1
      assert stats[child.id].block_count == 1
    end

    test "excludes constant blocks from variable count", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Constants"})
      block_fixture(sheet, %{type: "number", is_constant: true})
      block_fixture(sheet, %{type: "number", is_constant: false})

      stats = SheetStats.sheet_stats_for_project(project.id)

      assert stats[sheet.id].block_count == 2
      assert stats[sheet.id].variable_count == 1
    end

    test "counts table cell variables (rows × variable columns)", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Table Sheet"})
      # Table block auto-creates 1 row ("Row 1") + 1 column ("Value", type: number)
      # That's 1 × 1 = 1 table variable
      _table_block = block_fixture(sheet, %{type: "table"})

      stats = SheetStats.sheet_stats_for_project(project.id)

      # 1 block (the table), 1 table variable (1 row × 1 number column)
      assert stats[sheet.id].block_count == 1
      assert stats[sheet.id].variable_count == 1
    end

    test "counts table variables with multiple rows and columns", %{project: project} do
      alias Storyarn.Sheets.TableColumn
      alias Storyarn.Sheets.TableRow

      sheet = sheet_fixture(project, %{name: "Stats Sheet"})
      table_block = block_fixture(sheet, %{type: "table"})

      # Add a second variable column
      Repo.insert!(%TableColumn{
        block_id: table_block.id,
        name: "Modifier",
        slug: "modifier",
        type: "number",
        is_constant: false,
        position: 1
      })

      # Add more rows (auto-created "Row 1" already exists)
      for {name, pos} <- [{"STR", 1}, {"DEX", 2}] do
        Repo.insert!(%TableRow{
          block_id: table_block.id,
          name: name,
          slug: String.downcase(name),
          position: pos
        })
      end

      stats = SheetStats.sheet_stats_for_project(project.id)

      # 3 rows × 2 variable columns = 6 table variables
      assert stats[sheet.id].variable_count == 6
    end
  end

  describe "sheet_word_counts/1" do
    test "counts only sheet names and exported textual runtime values", %{
      project: project,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Hero", description: "Main hero"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Biography", "placeholder" => "Add story"},
        value: %{"content" => "Brave explorer"}
      })

      block_fixture(sheet, %{
        type: "select",
        config: %{
          "label" => "Class",
          "placeholder" => "Choose class",
          "options" => [
            %{"key" => "sword_master", "value" => "Sword Master"},
            %{"key" => "moon_mage", "value" => "Moon Mage"}
          ]
        }
      })

      table_block = table_block_fixture(sheet, %{label: "Stats"})
      table_column_fixture(table_block, %{name: "Combat Rank"})
      table_row_fixture(table_block, %{name: "Front Line"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "Moodboard", "placeholder" => ""}
        })

      asset = image_asset_fixture(project, user)

      Repo.insert!(%BlockGalleryImage{
        block_id: gallery_block.id,
        asset_id: asset.id,
        label: "Moonlit Dock",
        description: "Quiet blue harbor",
        position: 0
      })

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 3
    end

    test "strips HTML before counting", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Test"})

      block_fixture(sheet, %{
        type: "rich_text",
        config: %{"label" => "Body", "placeholder" => ""},
        value: %{"content" => "<p>Hello <strong>world</strong></p>"}
      })

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 3
    end

    test "uses denormalized runtime block counts and excludes editor-only text", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Hero"})

      runtime_block =
        block_fixture(sheet, %{
          type: "rich_text",
          is_constant: false,
          variable_name: "biography",
          value: %{"content" => "ignored during read"}
        })

      block_fixture(sheet, %{
        type: "text",
        is_constant: true,
        variable_name: "editor_note",
        value: %{"content" => "not exported"}
      })

      whitespace_block =
        block_fixture(sheet, %{
          type: "text",
          is_constant: false,
          variable_name: "temporary_name",
          value: %{"content" => "also not exported"}
        })

      Repo.update_all(from(block in Block, where: block.id == ^runtime_block.id),
        set: [word_count: 17]
      )

      Repo.update_all(from(block in Block, where: block.id == ^whitespace_block.id),
        set: [variable_name: "\t\n", word_count: 99]
      )

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 18
    end

    test "counts sheet name words even without blocks", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Combat Stats"})

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 2
    end

    test "excludes table row and column names", %{project: project} do
      alias Storyarn.Sheets.TableRow

      sheet = sheet_fixture(project, %{name: "Main"})
      table_block = table_block_fixture(sheet, %{label: "Table"})

      for name <- ["STR", "DEX", "INT", "WIS", "CON", "CHA"] do
        Repo.insert!(%TableRow{
          block_id: table_block.id,
          name: name,
          slug: String.downcase(name),
          position: 0
        })
      end

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 1
    end

    test "excludes table row names from inherited table blocks", %{project: project} do
      alias Storyarn.Sheets.TableRow

      parent_sheet = sheet_fixture(project, %{name: "Parent"})
      child_sheet = sheet_fixture(project, %{name: "Child"})

      parent_block = table_block_fixture(parent_sheet, %{label: "Table"})

      inherited_block =
        block_fixture(child_sheet, %{
          type: "table",
          inherited_from_block_id: parent_block.id,
          config: %{"label" => "Table", "collapsed" => false}
        })

      for {name, block_id} <- [{"STR", parent_block.id}, {"DEX", inherited_block.id}] do
        Repo.insert!(%TableRow{
          block_id: block_id,
          name: name,
          slug: String.downcase(name),
          position: 0
        })
      end

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[parent_sheet.id] == 1
      assert counts[child_sheet.id] == 1
    end
  end

  describe "referenced_block_ids_for_project/1" do
    test "returns block IDs with references", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Referenced Sheet"})
      block = block_fixture(sheet, %{type: "number", is_constant: false})

      # Insert a variable reference directly
      Repo.insert!(%VariableReference{
        source_type: "flow_node",
        source_id: System.unique_integer([:positive]),
        flow_node_id: nil,
        block_id: block.id,
        kind: "read",
        source_sheet: sheet.shortcut,
        source_variable: block.variable_name
      })

      referenced = SheetStats.referenced_block_ids_for_project(project.id)

      assert MapSet.member?(referenced, block.id)
    end

    test "returns empty MapSet when no references", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Unreferenced Sheet"})
      block_fixture(sheet, %{type: "number"})

      referenced = SheetStats.referenced_block_ids_for_project(project.id)

      assert MapSet.size(referenced) == 0
    end
  end

  describe "list_dashboard_health_findings/1" do
    test "returns empty leaves with the canonical code and severity", %{project: project} do
      sheet_fixture(project, %{name: "Empty One"})

      findings = SheetStats.list_dashboard_health_findings(project.id)

      assert finding = Enum.find(findings, &(&1.code == :empty_leaf_sheet))
      assert finding.severity == HealthChecker.severity_for(:empty_leaf_sheet)
      assert finding.details.sheet_name == "Empty One"
    end

    test "returns unused variables with the canonical code and severity", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Unused Vars"})
      block = block_fixture(sheet, %{type: "number", is_constant: false})

      findings = SheetStats.list_dashboard_health_findings(project.id)

      assert finding = Enum.find(findings, &(&1.code == :no_internal_variable_usages))
      assert finding.severity == HealthChecker.severity_for(:no_internal_variable_usages)
      assert finding.block_id == block.id
      assert finding.details.sheet_name == "Unused Vars"
    end

    test "includes unused table variables in health findings", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Unused Table"})
      block = block_fixture(sheet, %{type: "table", is_constant: false})

      findings = SheetStats.list_dashboard_health_findings(project.id)

      assert finding =
               Enum.find(
                 findings,
                 &(&1.code == :no_internal_variable_usages and &1.block_id == block.id)
               )

      assert finding.severity == HealthChecker.severity_for(:no_internal_variable_usages)
      assert finding.details.sheet_name == "Unused Table"
    end

    test "does not report tables referenced by formula bindings as unused", %{project: project} do
      target_sheet = sheet_fixture(project, %{name: "Formula Target"})
      target_table = table_block_fixture(target_sheet, %{label: "Stats"})
      target_row = hd(target_table.table_rows)
      target_column = hd(target_table.table_columns)

      source_sheet = sheet_fixture(project, %{name: "Formula Source"})
      source_table = table_block_fixture(source_sheet, %{label: "Calculations"})
      formula_column = table_column_fixture(source_table, %{name: "Total", type: "formula"})
      source_row = hd(source_table.table_rows)

      reference =
        Enum.join(
          [
            target_sheet.shortcut,
            target_table.variable_name,
            target_row.slug,
            target_column.slug
          ],
          "."
        )

      assert {:ok, _row} =
               Sheets.update_table_cell(source_row, formula_column.slug, %{
                 "expression" => "value",
                 "bindings" => %{
                   "value" => %{"type" => "variable", "ref" => reference}
                 }
               })

      findings = SheetStats.list_dashboard_health_findings(project.id)

      refute Enum.any?(
               findings,
               &(&1.code == :no_internal_variable_usages and &1.block_id == target_table.id)
             )
    end

    test "returns missing shortcuts with the canonical code and severity", %{project: project} do
      # Create a sheet, then nil out its shortcut directly
      sheet = sheet_fixture(project, %{name: "No Shortcut"})

      Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet.id),
        set: [shortcut: nil]
      )

      findings = SheetStats.list_dashboard_health_findings(project.id)

      assert finding = Enum.find(findings, &(&1.code == :missing_sheet_shortcut))
      assert finding.severity == HealthChecker.severity_for(:missing_sheet_shortcut)
      assert finding.details.sheet_name == "No Shortcut"
    end
  end
end
