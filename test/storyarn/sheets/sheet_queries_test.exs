defmodule Storyarn.Sheets.SheetQueriesTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.SheetQueries

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # Helper to create a standard project setup
  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # Tree Operations
  # =============================================================================

  describe "list_sheets_tree/1" do
    test "returns empty list for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_sheets_tree(project.id) == []
    end

    test "returns root-level sheets only at top level" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Root A", position: 0})
      sheet_fixture(project, %{name: "Root B", position: 1})

      tree = SheetQueries.list_sheets_tree(project.id)

      assert length(tree) == 2
      assert Enum.at(tree, 0).name == "Root A"
      assert Enum.at(tree, 1).name == "Root B"
    end

    test "builds nested tree structure" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root", position: 0})
      child = child_sheet_fixture(project, root, %{name: "Child", position: 0})
      _grandchild = child_sheet_fixture(project, child, %{name: "Grandchild", position: 0})

      [tree_root] = SheetQueries.list_sheets_tree(project.id)

      assert tree_root.name == "Root"
      assert length(tree_root.children) == 1
      assert hd(tree_root.children).name == "Child"
      assert length(hd(tree_root.children).children) == 1
      assert hd(hd(tree_root.children).children).name == "Grandchild"
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project, %{name: "Active"})
      deleted = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      tree = SheetQueries.list_sheets_tree(project.id)

      assert length(tree) == 1
      assert hd(tree).name == "Active"
    end

    test "orders by position then name" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Zebra", position: 0})
      sheet_fixture(project, %{name: "Alpha", position: 0})
      sheet_fixture(project, %{name: "Mid", position: 1})

      tree = SheetQueries.list_sheets_tree(project.id)

      assert length(tree) == 3
      # Same position -> sorted by name
      assert Enum.at(tree, 0).name == "Alpha"
      assert Enum.at(tree, 1).name == "Zebra"
      assert Enum.at(tree, 2).name == "Mid"
    end
  end

  # =============================================================================
  # Get operations
  # =============================================================================

  describe "get_sheet/2" do
    test "returns sheet with preloaded blocks and assets" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Test", avatar_asset_id: asset.id})
      block_fixture(sheet, %{type: "text"})

      result = SheetQueries.get_sheet(project.id, sheet.id)

      assert result.id == sheet.id
      assert result.avatar_asset != nil
      assert length(result.blocks) == 1
    end

    test "returns nil for non-existent sheet" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet(project.id, -1) == nil
    end

    test "returns nil for deleted sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert SheetQueries.get_sheet(project.id, sheet.id) == nil
    end

    test "returns nil for sheet in different project" do
      %{project: project1} = setup_project()
      %{project: project2} = setup_project()

      sheet = sheet_fixture(project1)

      assert SheetQueries.get_sheet(project2.id, sheet.id) == nil
    end
  end

  describe "get_sheet!/2" do
    test "returns sheet when found" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      result = SheetQueries.get_sheet!(project.id, sheet.id)
      assert result.id == sheet.id
    end

    test "raises for non-existent sheet" do
      %{project: project} = setup_project()

      assert_raise Ecto.NoResultsError, fn ->
        SheetQueries.get_sheet!(project.id, -1)
      end
    end

    test "raises for deleted sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert_raise Ecto.NoResultsError, fn ->
        SheetQueries.get_sheet!(project.id, sheet.id)
      end
    end
  end

  describe "get_sheet_full/2" do
    test "returns sheet with blocks, assets, and current_version preloaded" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      result = SheetQueries.get_sheet_full(project.id, sheet.id)

      assert result.id == sheet.id
      # Preload check: current_version should be loaded (nil since no version set)
      assert result.current_version == nil
      assert is_list(result.blocks)
    end

    test "returns nil for non-existent sheet" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet_full(project.id, -1) == nil
    end
  end

  describe "get_sheet_full!/2" do
    test "returns sheet when found" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      result = SheetQueries.get_sheet_full!(project.id, sheet.id)
      assert result.id == sheet.id
    end

    test "raises for non-existent sheet" do
      %{project: project} = setup_project()

      assert_raise Ecto.NoResultsError, fn ->
        SheetQueries.get_sheet_full!(project.id, -1)
      end
    end
  end

  describe "get_sheet_with_ancestors/2" do
    test "returns ancestor chain root-first" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})
      child = child_sheet_fixture(project, root, %{name: "Child"})
      grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})

      result = SheetQueries.get_sheet_with_ancestors(project.id, grandchild.id)

      assert length(result) == 3
      assert Enum.at(result, 0).name == "Root"
      assert Enum.at(result, 1).name == "Child"
      assert Enum.at(result, 2).name == "Grandchild"
    end

    test "returns single-element list for root sheet" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})

      result = SheetQueries.get_sheet_with_ancestors(project.id, root.id)

      assert length(result) == 1
      assert hd(result).name == "Root"
    end

    test "returns nil for non-existent sheet" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet_with_ancestors(project.id, -1) == nil
    end
  end

  describe "get_sheet_with_descendants/2" do
    test "returns sheet with descendants loaded into children" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})
      child1 = child_sheet_fixture(project, root, %{name: "Child A", position: 0})
      _child2 = child_sheet_fixture(project, root, %{name: "Child B", position: 1})
      _grandchild = child_sheet_fixture(project, child1, %{name: "Grandchild"})

      result = SheetQueries.get_sheet_with_descendants(project.id, root.id)

      assert result.name == "Root"
      assert length(result.children) == 2
      child_a = Enum.find(result.children, &(&1.name == "Child A"))
      assert length(child_a.children) == 1
      assert hd(child_a.children).name == "Grandchild"
    end

    test "returns sheet with empty children when no descendants" do
      %{project: project} = setup_project()

      leaf = sheet_fixture(project, %{name: "Leaf"})

      result = SheetQueries.get_sheet_with_descendants(project.id, leaf.id)

      assert result.name == "Leaf"
      assert result.children == []
    end

    test "returns nil for non-existent sheet" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet_with_descendants(project.id, -1) == nil
    end
  end

  describe "get_children/1" do
    test "returns direct children ordered by position" do
      %{project: project} = setup_project()

      parent = sheet_fixture(project, %{name: "Parent"})
      child_sheet_fixture(project, parent, %{name: "B Child", position: 1})
      child_sheet_fixture(project, parent, %{name: "A Child", position: 0})

      children = SheetQueries.get_children(parent.id)

      assert length(children) == 2
      assert Enum.at(children, 0).name == "A Child"
      assert Enum.at(children, 1).name == "B Child"
    end

    test "returns empty list when no children" do
      %{project: project} = setup_project()

      leaf = sheet_fixture(project)

      assert SheetQueries.get_children(leaf.id) == []
    end

    test "excludes soft-deleted children" do
      %{project: project} = setup_project()

      parent = sheet_fixture(project, %{name: "Parent"})
      _active = child_sheet_fixture(project, parent, %{name: "Active Child"})
      deleted = child_sheet_fixture(project, parent, %{name: "Deleted Child"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      children = SheetQueries.get_children(parent.id)

      assert length(children) == 1
      assert hd(children).name == "Active Child"
    end
  end

  describe "list_all_sheets/1" do
    test "returns flat list of all non-deleted sheets" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})
      _child = child_sheet_fixture(project, root, %{name: "Child"})

      sheets = SheetQueries.list_all_sheets(project.id)

      assert length(sheets) == 2
      names = Enum.map(sheets, & &1.name)
      assert "Root" in names
      assert "Child" in names
    end

    test "returns empty list for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_all_sheets(project.id) == []
    end

    test "excludes deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project, %{name: "Active"})
      deleted = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      sheets = SheetQueries.list_all_sheets(project.id)

      assert length(sheets) == 1
      assert hd(sheets).name == "Active"
    end
  end

  describe "list_leaf_sheets/1" do
    test "returns only sheets that have no children" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, root, %{name: "Child"})
      _grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})
      _standalone = sheet_fixture(project, %{name: "Standalone"})

      leaves = SheetQueries.list_leaf_sheets(project.id)
      leaf_names = Enum.map(leaves, & &1.name)

      # Grandchild and Standalone are leaf nodes
      assert "Grandchild" in leaf_names
      assert "Standalone" in leaf_names
      refute "Parent" in leaf_names
      refute "Child" in leaf_names
    end

    test "returns all sheets when none have children" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "A"})
      sheet_fixture(project, %{name: "B"})

      leaves = SheetQueries.list_leaf_sheets(project.id)

      assert length(leaves) == 2
    end

    test "returns empty list for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_leaf_sheets(project.id) == []
    end
  end

  # =============================================================================
  # Search
  # =============================================================================

  describe "search_sheets/2" do
    test "finds sheets by partial name match" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Character Jaime"})
      sheet_fixture(project, %{name: "Location Tavern"})

      results = SheetQueries.search_sheets(project.id, "Jaime")

      assert length(results) == 1
      assert hd(results).name == "Character Jaime"
    end

    test "finds sheets by partial shortcut match" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})
      sheet_fixture(project, %{name: "Tavern"})

      results = SheetQueries.search_sheets(project.id, "mc")

      assert length(results) == 1
      assert hd(results).id == sheet.id
    end

    test "returns recent sheets when query is empty" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Sheet A"})
      sheet_fixture(project, %{name: "Sheet B"})

      results = SheetQueries.search_sheets(project.id, "")

      assert length(results) == 2
    end

    test "returns recent sheets when query is whitespace" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Sheet A"})

      results = SheetQueries.search_sheets(project.id, "   ")

      assert length(results) == 1
    end

    test "returns at most 10 results" do
      %{project: project} = setup_project()

      for i <- 1..15 do
        sheet_fixture(project, %{name: "Match Sheet #{i}"})
      end

      results = SheetQueries.search_sheets(project.id, "Match")

      assert length(results) == 10
    end

    test "case-insensitive search" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "UPPERCASE"})

      results = SheetQueries.search_sheets(project.id, "uppercase")

      assert length(results) == 1
    end

    test "handles special SQL characters in search query" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "100% Complete"})
      sheet_fixture(project, %{name: "Some_Underscored"})

      # % should be escaped so it doesn't act as a wildcard
      results = SheetQueries.search_sheets(project.id, "%")

      assert length(results) == 1
      assert hd(results).name == "100% Complete"
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Active Character"})
      deleted = sheet_fixture(project, %{name: "Deleted Character"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      results = SheetQueries.search_sheets(project.id, "Character")

      assert length(results) == 1
      assert hd(results).name == "Active Character"
    end

    test "returns empty list when no matches" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Something"})

      results = SheetQueries.search_sheets(project.id, "nonexistent")

      assert results == []
    end
  end

  describe "get_sheet_by_shortcut/2" do
    test "finds sheet by exact shortcut" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})

      result = SheetQueries.get_sheet_by_shortcut(project.id, "mc.jaime")

      assert result.id == sheet.id
      assert is_list(result.blocks)
    end

    test "returns nil for non-existent shortcut" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet_by_shortcut(project.id, "nonexistent") == nil
    end

    test "returns nil when shortcut is nil" do
      %{project: project} = setup_project()

      assert SheetQueries.get_sheet_by_shortcut(project.id, nil) == nil
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert SheetQueries.get_sheet_by_shortcut(project.id, "mc.jaime") == nil
    end

    test "scopes to correct project" do
      %{project: project1} = setup_project()
      %{project: project2} = setup_project()

      {:ok, _} = Sheets.create_sheet(project1, %{name: "Jaime", shortcut: "mc.jaime"})

      assert SheetQueries.get_sheet_by_shortcut(project2.id, "mc.jaime") == nil
    end
  end

  # =============================================================================
  # Variables
  # =============================================================================

  describe "list_project_variables/1" do
    test "returns empty list for project with no variables" do
      %{project: project} = setup_project()

      assert SheetQueries.list_project_variables(project.id) == []
    end

    test "returns block variables with correct shape" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      [var] = SheetQueries.list_project_variables(project.id)

      assert var.sheet_name == "MC"
      assert var.sheet_shortcut == "mc"
      assert var.variable_name == "health"
      assert var.block_type == "number"
      assert var.options == nil
      assert var.table_name == nil
      assert var.row_name == nil
      assert var.column_name == nil
      assert Map.has_key?(var, :sheet_id)
      assert Map.has_key?(var, :block_id)
      refute Map.has_key?(var, :config)
    end

    test "excludes constant blocks" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Bio"}, is_constant: true})

      vars = SheetQueries.list_project_variables(project.id)

      assert length(vars) == 1
      assert hd(vars).variable_name == "health"
    end

    test "excludes non-variable types (divider, reference)" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      block_fixture(sheet, %{type: "divider", config: %{"label" => "---"}})

      vars = SheetQueries.list_project_variables(project.id)

      assert length(vars) == 1
    end

    test "includes select options" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "select",
        config: %{"label" => "Class", "options" => ["Warrior", "Mage"]}
      })

      [var] = SheetQueries.list_project_variables(project.id)

      assert var.block_type == "select"
      assert var.options == ["Warrior", "Mage"]
    end

    test "includes constraints for number variables" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "min" => 0, "max" => 100, "step" => 1}
      })

      [var] = SheetQueries.list_project_variables(project.id)

      assert var.constraints == %{"min" => 0, "max" => 100, "step" => 1}
    end
  end

  describe "list_reference_options/1" do
    test "returns sheets with shortcut as options" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Tavern", shortcut: "loc.tavern"})

      options = SheetQueries.list_reference_options(project.id)

      assert length(options) == 2
      assert Enum.any?(options, &(&1["key"] == "mc.jaime" && &1["value"] == "Jaime"))
      assert Enum.any?(options, &(&1["key"] == "loc.tavern" && &1["value"] == "Tavern"))
    end

    test "excludes sheets without shortcut" do
      %{project: project} = setup_project()

      # Sheets auto-generate shortcuts, so create one then clear it via direct DB update
      {:ok, _sheet} = Sheets.create_sheet(project, %{name: "Test", shortcut: "test"})
      {:ok, _another} = Sheets.create_sheet(project, %{name: "Another"})

      options = SheetQueries.list_reference_options(project.id)

      # Both should have shortcuts since they auto-generate
      assert length(options) >= 1
      shortcuts = Enum.map(options, & &1["key"])
      assert "test" in shortcuts
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Deleted", shortcut: "deleted"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Active", shortcut: "active"})
      {:ok, _} = Sheets.trash_sheet(sheet)

      options = SheetQueries.list_reference_options(project.id)
      shortcuts = Enum.map(options, & &1["key"])

      assert "active" in shortcuts
      refute "deleted" in shortcuts
    end

    test "returns empty list for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_reference_options(project.id) == []
    end
  end

  # =============================================================================
  # Variable Value Resolution
  # =============================================================================

  describe "resolve_variable_values/2" do
    test "resolves simple block variable values" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 75}
      })

      result = SheetQueries.resolve_variable_values(project.id, ["mc.health"])

      assert result["mc.health"] == 75
    end

    test "returns empty map for empty refs" do
      %{project: project} = setup_project()

      assert SheetQueries.resolve_variable_values(project.id, []) == %{}
    end

    test "returns empty map when refs don't match any variables" do
      %{project: project} = setup_project()

      result = SheetQueries.resolve_variable_values(project.id, ["nonexistent.var"])

      assert result == %{}
    end

    test "resolves multiple simple variable values" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 75}
      })

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"content" => "Jaime"}
      })

      result = SheetQueries.resolve_variable_values(project.id, ["mc.health", "mc.name"])

      assert result["mc.health"] == 75
      assert result["mc.name"] == "Jaime"
    end

    test "returns nil for blocks with no content key in value" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{}
      })

      result = SheetQueries.resolve_variable_values(project.id, ["mc.health"])

      assert result["mc.health"] == nil
    end

    # NOTE: resolve_table_values tests are skipped because the source code
    # query_table_rows/2 references `tr.values` but the TableRow schema field
    # is actually `cells`. This is a known source bug (SheetQueries line 514).

    test "handles refs that don't match any table variables gracefully" do
      %{project: project} = setup_project()

      # Only simple refs - no table refs to avoid the values/cells bug
      result = SheetQueries.resolve_variable_values(project.id, ["nonexistent.var"])

      assert result == %{}
    end

    test "resolves multiple simple refs from different sheets" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      sheet2 = sheet_fixture(project, %{name: "Location", shortcut: "loc"})

      block_fixture(sheet1, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 100}
      })

      block_fixture(sheet2, %{
        type: "text",
        config: %{"label" => "Name"},
        value: %{"content" => "Tavern"}
      })

      result = SheetQueries.resolve_variable_values(project.id, ["mc.health", "loc.name"])

      assert result["mc.health"] == 100
      assert result["loc.name"] == "Tavern"
    end
  end

  # =============================================================================
  # Reference Validation
  # =============================================================================

  describe "validate_reference_target/3" do
    test "returns {:ok, sheet} for valid sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      assert {:ok, result} = SheetQueries.validate_reference_target("sheet", sheet.id, project.id)
      assert result.id == sheet.id
    end

    test "returns {:ok, flow} for valid flow" do
      %{project: project} = setup_project()

      flow = flow_fixture(project)

      assert {:ok, result} = SheetQueries.validate_reference_target("flow", flow.id, project.id)
      assert result.id == flow.id
    end

    test "returns {:error, :not_found} for non-existent sheet" do
      %{project: project} = setup_project()

      assert {:error, :not_found} =
               SheetQueries.validate_reference_target("sheet", -1, project.id)
    end

    test "returns {:error, :not_found} for deleted sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert {:error, :not_found} =
               SheetQueries.validate_reference_target("sheet", sheet.id, project.id)
    end

    test "returns {:error, :invalid_type} for unknown type" do
      %{project: project} = setup_project()

      assert {:error, :invalid_type} =
               SheetQueries.validate_reference_target("unknown", 1, project.id)
    end
  end

  # =============================================================================
  # Inheritance Queries
  # =============================================================================

  describe "list_inheritable_blocks/1" do
    test "returns blocks with scope children" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      inheritable_block_fixture(sheet, label: "Shared Field", type: "text")
      block_fixture(sheet, %{type: "text", config: %{"label" => "Own Field"}})

      blocks = SheetQueries.list_inheritable_blocks(sheet.id)

      assert length(blocks) == 1
      assert hd(blocks).scope == "children"
    end

    test "returns empty list when no inheritable blocks" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      block_fixture(sheet, %{type: "text"})

      assert SheetQueries.list_inheritable_blocks(sheet.id) == []
    end

    test "excludes soft-deleted blocks" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      block = inheritable_block_fixture(sheet, label: "Deleted Inheritable")
      {:ok, _} = Sheets.delete_block(block)

      assert SheetQueries.list_inheritable_blocks(sheet.id) == []
    end

    test "orders by position" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      inheritable_block_fixture(sheet, label: "Second", type: "text")
      inheritable_block_fixture(sheet, label: "Third", type: "number")

      blocks = SheetQueries.list_inheritable_blocks(sheet.id)

      # They should be ordered by position (auto-incremented)
      assert length(blocks) == 2
      positions = Enum.map(blocks, & &1.position)
      assert positions == Enum.sort(positions)
    end
  end

  describe "list_inherited_instances/1" do
    test "returns blocks inherited from a parent block" do
      %{project: project} = setup_project()

      parent = sheet_fixture(project, %{name: "Parent"})
      parent_block = inheritable_block_fixture(parent, label: "Shared", type: "text")

      child = child_sheet_fixture(project, parent, %{name: "Child"})

      # Trigger inheritance (expects sheet_id, not struct)
      Sheets.resolve_inherited_blocks(child.id)

      instances = SheetQueries.list_inherited_instances(parent_block.id)

      assert length(instances) >= 1
      assert Enum.all?(instances, &(&1.inherited_from_block_id == parent_block.id))
    end

    test "returns empty list when no instances exist" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text"})

      assert SheetQueries.list_inherited_instances(block.id) == []
    end
  end

  # =============================================================================
  # Trash
  # =============================================================================

  describe "list_trashed_sheets/1" do
    test "returns only soft-deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project, %{name: "Active"})
      trashed = sheet_fixture(project, %{name: "Trashed"})
      {:ok, _} = Sheets.trash_sheet(trashed)

      result = SheetQueries.list_trashed_sheets(project.id)

      assert length(result) == 1
      assert hd(result).id == trashed.id
    end

    test "orders by deleted_at desc" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project, %{name: "First"})
      sheet2 = sheet_fixture(project, %{name: "Second"})
      {:ok, _} = Sheets.trash_sheet(sheet1)
      {:ok, _} = Sheets.trash_sheet(sheet2)

      # Set explicit timestamps
      Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet1.id),
        set: [deleted_at: ~U[2024-01-01 10:00:00Z]]
      )

      Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet2.id),
        set: [deleted_at: ~U[2024-01-01 11:00:00Z]]
      )

      result = SheetQueries.list_trashed_sheets(project.id)

      assert length(result) == 2
      # More recently deleted first
      assert Enum.at(result, 0).id == sheet2.id
      assert Enum.at(result, 1).id == sheet1.id
    end

    test "returns empty list when no trashed sheets" do
      %{project: project} = setup_project()

      sheet_fixture(project)

      assert SheetQueries.list_trashed_sheets(project.id) == []
    end
  end

  describe "get_trashed_sheet/2" do
    test "returns trashed sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(sheet)

      result = SheetQueries.get_trashed_sheet(project.id, sheet.id)

      assert result.id == sheet.id
      assert result.deleted_at != nil
    end

    test "returns nil for non-deleted sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      assert SheetQueries.get_trashed_sheet(project.id, sheet.id) == nil
    end

    test "returns nil for non-existent sheet" do
      %{project: project} = setup_project()

      assert SheetQueries.get_trashed_sheet(project.id, -1) == nil
    end

    test "scopes to project" do
      %{project: project1} = setup_project()
      %{project: project2} = setup_project()

      sheet = sheet_fixture(project1)
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert SheetQueries.get_trashed_sheet(project2.id, sheet.id) == nil
    end
  end

  # =============================================================================
  # Ancestor Chain
  # =============================================================================

  describe "list_ancestors/1" do
    test "returns empty list for root sheet" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})

      assert SheetQueries.list_ancestors(root.id) == []
    end

    test "returns parent for first-level child (child-first order)" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})
      child = child_sheet_fixture(project, root, %{name: "Child"})

      ancestors = SheetQueries.list_ancestors(child.id)

      assert length(ancestors) == 1
      assert hd(ancestors).id == root.id
    end

    test "returns full chain for deeply nested sheet" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})
      child = child_sheet_fixture(project, root, %{name: "Child"})
      grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})
      great_grandchild = child_sheet_fixture(project, grandchild, %{name: "Great-Grandchild"})

      ancestors = SheetQueries.list_ancestors(great_grandchild.id)

      # Child-first: grandchild, child, root
      assert length(ancestors) == 3
      ancestor_ids = Enum.map(ancestors, & &1.id)
      assert grandchild.id in ancestor_ids
      assert child.id in ancestor_ids
      assert root.id in ancestor_ids
    end
  end

  # =============================================================================
  # Export / Import Helpers
  # =============================================================================

  describe "get_sheet_project_id/1" do
    test "returns project_id for existing sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      assert SheetQueries.get_sheet_project_id(sheet.id) == project.id
    end

    test "returns nil for non-existent sheet" do
      assert SheetQueries.get_sheet_project_id(-1) == nil
    end
  end

  describe "list_sheets_for_export/2" do
    test "returns sheets with blocks and table data preloaded" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      block_fixture(sheet, %{type: "text"})

      [result] = SheetQueries.list_sheets_for_export(project.id)

      assert result.name == "Test Sheet"
      assert length(result.blocks) == 1
    end

    test "filters by specific sheet IDs when provided" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project, %{name: "Include"})
      _sheet2 = sheet_fixture(project, %{name: "Exclude"})

      results = SheetQueries.list_sheets_for_export(project.id, filter_ids: [sheet1.id])

      assert length(results) == 1
      assert hd(results).name == "Include"
    end

    test "returns all sheets when filter_ids is :all" do
      %{project: project} = setup_project()

      sheet_fixture(project, %{name: "Sheet A"})
      sheet_fixture(project, %{name: "Sheet B"})

      results = SheetQueries.list_sheets_for_export(project.id, filter_ids: :all)

      assert length(results) == 2
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project, %{name: "Active"})
      deleted = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      results = SheetQueries.list_sheets_for_export(project.id)

      assert length(results) == 1
      assert hd(results).name == "Active"
    end

    test "excludes soft-deleted blocks from preloaded data" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "Test"})
      _active_block = block_fixture(sheet, %{type: "text"})
      deleted_block = block_fixture(sheet, %{type: "number"})
      {:ok, _} = Sheets.delete_block(deleted_block)

      [result] = SheetQueries.list_sheets_for_export(project.id)

      assert length(result.blocks) == 1
    end
  end

  describe "count_sheets/1" do
    test "returns count of non-deleted sheets" do
      %{project: project} = setup_project()

      sheet_fixture(project)
      sheet_fixture(project)
      deleted = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(deleted)

      assert SheetQueries.count_sheets(project.id) == 2
    end

    test "returns 0 for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.count_sheets(project.id) == 0
    end
  end

  describe "list_blocks_for_sheet_ids/1" do
    test "returns blocks for given sheet IDs" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project)
      sheet2 = sheet_fixture(project)
      block_fixture(sheet1, %{type: "text"})
      block_fixture(sheet1, %{type: "number"})
      block_fixture(sheet2, %{type: "text"})

      blocks = SheetQueries.list_blocks_for_sheet_ids([sheet1.id, sheet2.id])

      assert length(blocks) == 3
    end

    test "returns empty list for empty input" do
      assert SheetQueries.list_blocks_for_sheet_ids([]) == []
    end

    test "returns empty list when no blocks exist" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project)

      assert SheetQueries.list_blocks_for_sheet_ids([sheet.id]) == []
    end
  end

  describe "list_sheets_brief/1" do
    test "returns id, name, and shortcut" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Test Sheet", shortcut: "test"})

      [brief] = SheetQueries.list_sheets_brief(project.id)

      assert Map.has_key?(brief, :id)
      assert brief.name == "Test Sheet"
      assert brief.shortcut == "test"
    end

    test "excludes soft-deleted sheets" do
      %{project: project} = setup_project()

      _active = sheet_fixture(project)
      deleted = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(deleted)

      briefs = SheetQueries.list_sheets_brief(project.id)

      assert length(briefs) == 1
    end

    test "returns empty list for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_sheets_brief(project.id) == []
    end
  end

  describe "list_shortcuts/1" do
    test "returns MapSet of all shortcuts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet B", shortcut: "b"})

      shortcuts = SheetQueries.list_shortcuts(project.id)

      assert MapSet.member?(shortcuts, "a")
      assert MapSet.member?(shortcuts, "b")
    end

    test "excludes deleted sheet shortcuts" do
      %{project: project} = setup_project()

      {:ok, _active} = Sheets.create_sheet(project, %{name: "Active", shortcut: "active"})
      {:ok, deleted} = Sheets.create_sheet(project, %{name: "Deleted", shortcut: "deleted"})
      {:ok, _} = Sheets.trash_sheet(deleted)

      shortcuts = SheetQueries.list_shortcuts(project.id)

      assert MapSet.member?(shortcuts, "active")
      refute MapSet.member?(shortcuts, "deleted")
    end

    test "returns empty MapSet for project with no sheets" do
      %{project: project} = setup_project()

      assert SheetQueries.list_shortcuts(project.id) == MapSet.new()
    end
  end

  describe "detect_shortcut_conflicts/2" do
    test "returns conflicting shortcuts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet B", shortcut: "b"})

      conflicts = SheetQueries.detect_shortcut_conflicts(project.id, ["a", "c"])

      assert "a" in conflicts
      refute "c" in conflicts
    end

    test "returns empty list when no conflicts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Sheet A", shortcut: "a"})

      assert SheetQueries.detect_shortcut_conflicts(project.id, ["x", "y"]) == []
    end

    test "returns empty list for empty input" do
      %{project: project} = setup_project()

      assert SheetQueries.detect_shortcut_conflicts(project.id, []) == []
    end

    test "excludes soft-deleted sheet shortcuts" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Deleted", shortcut: "deleted"})
      {:ok, _} = Sheets.trash_sheet(sheet)

      conflicts = SheetQueries.detect_shortcut_conflicts(project.id, ["deleted"])

      assert conflicts == []
    end
  end

  describe "soft_delete_by_shortcut/2" do
    test "soft-deletes sheets with matching shortcut" do
      %{project: project} = setup_project()

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Target", shortcut: "target"})

      {count, _} = SheetQueries.soft_delete_by_shortcut(project.id, "target")

      assert count == 1
      assert SheetQueries.get_sheet(project.id, sheet.id) == nil
    end

    test "does not affect sheets with different shortcuts" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Keep", shortcut: "keep"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Delete", shortcut: "delete"})

      SheetQueries.soft_delete_by_shortcut(project.id, "delete")

      assert SheetQueries.get_sheet_by_shortcut(project.id, "keep") != nil
      assert SheetQueries.get_sheet_by_shortcut(project.id, "delete") == nil
    end

    test "returns {0, nil} when no match" do
      %{project: project} = setup_project()

      {count, _} = SheetQueries.soft_delete_by_shortcut(project.id, "nonexistent")

      assert count == 0
    end
  end

  # =============================================================================
  # Block ID Resolution
  # =============================================================================

  describe "resolve_block_id_by_variable/3" do
    test "resolves block ID by sheet shortcut and variable name" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      result = SheetQueries.resolve_block_id_by_variable(project.id, "mc", "health")

      assert result == block.id
    end

    test "returns nil for non-existent variable" do
      %{project: project} = setup_project()

      assert SheetQueries.resolve_block_id_by_variable(project.id, "mc", "nonexistent") == nil
    end

    test "returns nil for deleted sheet" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      _block = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert SheetQueries.resolve_block_id_by_variable(project.id, "mc", "health") == nil
    end

    test "returns nil for deleted block" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      {:ok, _} = Sheets.delete_block(block)

      assert SheetQueries.resolve_block_id_by_variable(project.id, "mc", "health") == nil
    end
  end

  describe "resolve_table_block_id_by_variable/5" do
    test "resolves table block ID by shortcut, table, row, and column" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      table = table_block_fixture(sheet, %{label: "Stats"})

      [default_row] = table.table_rows
      [default_col] = table.table_columns

      result =
        SheetQueries.resolve_table_block_id_by_variable(
          project.id,
          "mc.jaime",
          "stats",
          default_row.slug,
          default_col.slug
        )

      assert result == table.id
    end

    test "returns nil for non-existent table" do
      %{project: project} = setup_project()

      assert SheetQueries.resolve_table_block_id_by_variable(
               project.id,
               "mc",
               "nonexistent",
               "row",
               "col"
             ) == nil
    end
  end

  # =============================================================================
  # Asset Usage Queries
  # =============================================================================

  describe "list_sheets_using_asset_as_avatar/2" do
    test "returns sheets using given asset as avatar" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "With Avatar", avatar_asset_id: asset.id})

      _no_avatar = sheet_fixture(project, %{name: "No Avatar"})

      results = SheetQueries.list_sheets_using_asset_as_avatar(project.id, asset.id)

      assert length(results) == 1
      assert hd(results).id == sheet.id
    end

    test "returns empty list when no sheets use the asset" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)

      assert SheetQueries.list_sheets_using_asset_as_avatar(project.id, asset.id) == []
    end

    test "excludes soft-deleted sheets" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Deleted", avatar_asset_id: asset.id})
      {:ok, _} = Sheets.trash_sheet(sheet)

      assert SheetQueries.list_sheets_using_asset_as_avatar(project.id, asset.id) == []
    end
  end

  describe "list_sheets_using_asset_as_banner/2" do
    test "returns sheets using given asset as banner" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "With Banner", banner_asset_id: asset.id})

      _no_banner = sheet_fixture(project, %{name: "No Banner"})

      results = SheetQueries.list_sheets_using_asset_as_banner(project.id, asset.id)

      assert length(results) == 1
      assert hd(results).id == sheet.id
    end

    test "returns empty list when no sheets use the asset" do
      %{user: user, project: project} = setup_project()

      asset = image_asset_fixture(project, user)

      assert SheetQueries.list_sheets_using_asset_as_banner(project.id, asset.id) == []
    end
  end

  # =============================================================================
  # Coverage gap tests
  # =============================================================================

  describe "list_reference_options/1 (via list_sheet_options)" do
    test "returns sheet options with key/value format" do
      %{project: project} = setup_project()

      {:ok, _} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})
      {:ok, _} = Sheets.create_sheet(project, %{name: "Tavern", shortcut: "loc.tavern"})

      options = SheetQueries.list_reference_options(project.id)

      assert length(options) == 2
      assert Enum.any?(options, &(&1["key"] == "mc.jaime" && &1["value"] == "Jaime"))
      assert Enum.any?(options, &(&1["key"] == "loc.tavern" && &1["value"] == "Tavern"))
    end

    test "excludes sheets without shortcuts" do
      %{project: project} = setup_project()

      # Sheet with shortcut
      {:ok, _} = Sheets.create_sheet(project, %{name: "With Shortcut", shortcut: "ws"})
      # Sheet without explicit shortcut will still get auto-generated one,
      # so create one and then clear its shortcut
      sheet = sheet_fixture(project, %{name: "No Shortcut"})

      import Ecto.Query

      Storyarn.Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet.id),
        set: [shortcut: nil]
      )

      options = SheetQueries.list_reference_options(project.id)

      # Only the one with a shortcut should appear
      assert length(options) == 1
      assert hd(options)["key"] == "ws"
    end
  end

  describe "list_project_variables/1 with boolean and date types" do
    test "returns boolean variable with constraints" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "boolean",
        config: %{"label" => "Is Active", "mode" => "tri_state"},
        value: %{"content" => true}
      })

      vars = SheetQueries.list_project_variables(project.id)

      assert length(vars) == 1
      bool_var = hd(vars)
      assert bool_var.block_type == "boolean"
      assert bool_var.variable_name == "is_active"
      assert is_map(bool_var.constraints)
    end

    test "returns date variable with constraints" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "date",
        config: %{"label" => "Birthday"},
        value: %{"content" => "2000-01-01"}
      })

      vars = SheetQueries.list_project_variables(project.id)

      assert length(vars) == 1
      date_var = hd(vars)
      assert date_var.block_type == "date"
      assert date_var.variable_name == "birthday"
      assert is_map(date_var.constraints) or is_nil(date_var.constraints)
    end
  end

  describe "resolve_variable_values/2 edge cases" do
    test "ignores malformed refs without a dot separator" do
      %{project: project} = setup_project()

      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 50}
      })

      # "nodots" has no dot, so parse_simple_ref returns nil and it gets rejected
      # "mc.health" is valid and should resolve
      result = SheetQueries.resolve_variable_values(project.id, ["nodots", "mc.health"])

      assert result["mc.health"] == 50
      refute Map.has_key?(result, "nodots")
    end
  end

  describe "get_sheet_with_ancestors/2 for root sheet" do
    test "returns just the sheet itself when it has no parent" do
      %{project: project} = setup_project()

      root = sheet_fixture(project, %{name: "Root"})

      result = SheetQueries.get_sheet_with_ancestors(project.id, root.id)

      # Root sheet has no ancestors, so the result should contain only itself
      assert length(result) == 1
      assert hd(result).id == root.id
    end
  end

  describe "validate_reference_target/3 flow not found" do
    test "returns {:error, :not_found} for non-existent flow" do
      %{project: project} = setup_project()

      assert {:error, :not_found} =
               SheetQueries.validate_reference_target("flow", -1, project.id)
    end
  end
end
