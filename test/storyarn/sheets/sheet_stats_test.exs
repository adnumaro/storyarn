defmodule Storyarn.Sheets.SheetStatsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Sheets.SheetStats

  setup do
    user = user_fixture()
    project = project_fixture(user) |> Repo.preload(:workspace)
    %{project: project}
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
  end

  describe "sheet_word_counts/1" do
    test "counts words in text/rich_text blocks", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Words Sheet"})

      block_fixture(sheet, %{
        type: "text",
        value: %{"content" => "hello world foo"}
      })

      block_fixture(sheet, %{
        type: "rich_text",
        value: %{"content" => "bar baz"}
      })

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 5
    end

    test "strips HTML before counting", %{project: project} do
      sheet = sheet_fixture(project, %{name: "HTML Sheet"})

      block_fixture(sheet, %{
        type: "rich_text",
        value: %{"content" => "<p>Hello <strong>world</strong></p>"}
      })

      counts = SheetStats.sheet_word_counts(project.id)

      assert counts[sheet.id] == 2
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

  describe "detect_sheet_issues/1" do
    test "detects empty sheets", %{project: project} do
      sheet_fixture(project, %{name: "Empty One"})

      issues = SheetStats.detect_sheet_issues(project.id)

      empty_issues = Enum.filter(issues, &(&1.issue_type == :empty_sheet))
      assert empty_issues != []
      assert Enum.any?(empty_issues, &(&1.sheet_name == "Empty One"))
    end

    test "detects unused variables", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Unused Vars"})
      block_fixture(sheet, %{type: "number", is_constant: false})

      issues = SheetStats.detect_sheet_issues(project.id)

      unused_issues = Enum.filter(issues, &(&1.issue_type == :unused_variable))
      assert unused_issues != []
    end

    test "detects missing shortcuts", %{project: project} do
      # Create a sheet, then nil out its shortcut directly
      sheet = sheet_fixture(project, %{name: "No Shortcut"})

      Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet.id),
        set: [shortcut: nil]
      )

      issues = SheetStats.detect_sheet_issues(project.id)

      missing_issues = Enum.filter(issues, &(&1.issue_type == :missing_shortcut))
      assert missing_issues != []
      assert Enum.any?(missing_issues, &(&1.sheet_name == "No Shortcut"))
    end
  end
end
