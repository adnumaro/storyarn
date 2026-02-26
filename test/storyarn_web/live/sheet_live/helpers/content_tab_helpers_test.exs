defmodule StoryarnWeb.SheetLive.Helpers.ContentTabHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ── to_integer/1 ─────────────────────────────────────────────────────

  describe "to_integer/1" do
    test "parses binary integer" do
      assert ContentTabHelpers.to_integer("42") == 42
    end

    test "returns nil for non-numeric string" do
      assert ContentTabHelpers.to_integer("abc") == nil
    end

    test "returns nil for partially numeric string" do
      assert ContentTabHelpers.to_integer("42abc") == nil
    end

    test "returns nil for empty string" do
      assert ContentTabHelpers.to_integer("") == nil
    end

    test "returns integer as-is" do
      assert ContentTabHelpers.to_integer(99) == 99
    end

    test "returns nil for nil" do
      assert ContentTabHelpers.to_integer(nil) == nil
    end

    test "returns nil for atom" do
      assert ContentTabHelpers.to_integer(:foo) == nil
    end

    test "returns nil for float" do
      assert ContentTabHelpers.to_integer(3.14) == nil
    end

    test "returns nil for list" do
      assert ContentTabHelpers.to_integer([1, 2]) == nil
    end

    test "parses negative integer string" do
      assert ContentTabHelpers.to_integer("-5") == -5
    end

    test "parses zero" do
      assert ContentTabHelpers.to_integer("0") == 0
    end
  end

  # ── column_grid_class/1 ──────────────────────────────────────────────

  describe "column_grid_class/1" do
    test "returns 2-column class" do
      assert ContentTabHelpers.column_grid_class(2) == "sm:grid-cols-2"
    end

    test "returns 3-column class" do
      assert ContentTabHelpers.column_grid_class(3) == "sm:grid-cols-3"
    end

    test "returns 1-column class for 1" do
      assert ContentTabHelpers.column_grid_class(1) == "sm:grid-cols-1"
    end

    test "returns 1-column class for 0" do
      assert ContentTabHelpers.column_grid_class(0) == "sm:grid-cols-1"
    end

    test "returns 1-column class for 4" do
      assert ContentTabHelpers.column_grid_class(4) == "sm:grid-cols-1"
    end
  end

  # ── group_blocks_for_layout/1 ────────────────────────────────────────

  describe "group_blocks_for_layout/1" do
    test "returns full_width items for blocks without column_group_id" do
      blocks = [
        %{id: 1, column_group_id: nil, column_index: 0, type: "text"},
        %{id: 2, column_group_id: nil, column_index: 0, type: "number"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)

      assert length(result) == 2
      assert Enum.all?(result, &(&1.type == :full_width))
      assert Enum.at(result, 0).block.id == 1
      assert Enum.at(result, 1).block.id == 2
    end

    test "groups blocks with same column_group_id into column_group" do
      blocks = [
        %{id: 1, column_group_id: "g1", column_index: 0, type: "text"},
        %{id: 2, column_group_id: "g1", column_index: 1, type: "number"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)

      assert length(result) == 1
      group = hd(result)
      assert group.type == :column_group
      assert group.group_id == "g1"
      assert length(group.blocks) == 2
      assert group.column_count == 2
    end

    test "single block in group renders as full_width" do
      blocks = [
        %{id: 1, column_group_id: "g1", column_index: 0, type: "text"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)

      assert length(result) == 1
      assert hd(result).type == :full_width
    end

    test "caps column_count at 3" do
      blocks = [
        %{id: 1, column_group_id: "g1", column_index: 0, type: "text"},
        %{id: 2, column_group_id: "g1", column_index: 1, type: "number"},
        %{id: 3, column_group_id: "g1", column_index: 2, type: "text"},
        %{id: 4, column_group_id: "g1", column_index: 3, type: "boolean"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)

      assert length(result) == 1
      assert hd(result).column_count == 3
    end

    test "sorts blocks within column group by column_index" do
      blocks = [
        %{id: 2, column_group_id: "g1", column_index: 1, type: "number"},
        %{id: 1, column_group_id: "g1", column_index: 0, type: "text"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)
      group = hd(result)

      assert Enum.map(group.blocks, & &1.id) == [1, 2]
    end

    test "handles mixed full_width and column groups" do
      blocks = [
        %{id: 1, column_group_id: nil, column_index: 0, type: "divider"},
        %{id: 2, column_group_id: "g1", column_index: 0, type: "text"},
        %{id: 3, column_group_id: "g1", column_index: 1, type: "number"},
        %{id: 4, column_group_id: nil, column_index: 0, type: "text"}
      ]

      result = ContentTabHelpers.group_blocks_for_layout(blocks)

      assert length(result) == 3
      assert Enum.at(result, 0).type == :full_width
      assert Enum.at(result, 1).type == :column_group
      assert Enum.at(result, 2).type == :full_width
    end

    test "returns empty list for empty input" do
      assert ContentTabHelpers.group_blocks_for_layout([]) == []
    end
  end

  # ── sanitize_column_item/2 ───────────────────────────────────────────

  describe "sanitize_column_item/2" do
    test "returns sanitized item when block exists" do
      blocks_by_id = %{
        1 => %{id: 1, type: "text"}
      }

      item = %{"id" => "1", "column_group_id" => "g1", "column_index" => 0}
      result = ContentTabHelpers.sanitize_column_item(item, blocks_by_id)

      assert result == %{id: 1, column_group_id: "g1", column_index: 0}
    end

    test "returns nil when block not found" do
      blocks_by_id = %{}
      item = %{"id" => "999", "column_group_id" => "g1", "column_index" => 0}

      assert ContentTabHelpers.sanitize_column_item(item, blocks_by_id) == nil
    end

    test "clears column_group_id for divider blocks" do
      blocks_by_id = %{
        1 => %{id: 1, type: "divider"}
      }

      item = %{"id" => "1", "column_group_id" => "g1", "column_index" => 2}
      result = ContentTabHelpers.sanitize_column_item(item, blocks_by_id)

      assert result.column_group_id == nil
      assert result.column_index == 0
    end

    test "clears column_group_id for table blocks" do
      blocks_by_id = %{
        1 => %{id: 1, type: "table"}
      }

      item = %{"id" => "1", "column_group_id" => "g1", "column_index" => 1}
      result = ContentTabHelpers.sanitize_column_item(item, blocks_by_id)

      assert result.column_group_id == nil
      assert result.column_index == 0
    end

    test "sets column_index to 0 when column_group_id is nil" do
      blocks_by_id = %{
        1 => %{id: 1, type: "text"}
      }

      item = %{"id" => "1", "column_group_id" => nil, "column_index" => 5}
      result = ContentTabHelpers.sanitize_column_item(item, blocks_by_id)

      assert result.column_group_id == nil
      assert result.column_index == 0
    end

    test "defaults column_index to 0 when missing" do
      blocks_by_id = %{
        1 => %{id: 1, type: "text"}
      }

      item = %{"id" => "1", "column_group_id" => "g1"}
      result = ContentTabHelpers.sanitize_column_item(item, blocks_by_id)

      assert result.column_index == 0
    end
  end

  # ── validate_column_group_blocks/1 ───────────────────────────────────

  describe "validate_column_group_blocks/1" do
    test "returns :ok for valid blocks" do
      blocks = [
        %{type: "text", column_group_id: nil},
        %{type: "number", column_group_id: nil}
      ]

      assert ContentTabHelpers.validate_column_group_blocks(blocks) == :ok
    end

    test "returns error when any block is nil" do
      blocks = [%{type: "text", column_group_id: nil}, nil]
      assert {:error, _msg} = ContentTabHelpers.validate_column_group_blocks(blocks)
    end

    test "returns error for divider blocks" do
      blocks = [
        %{type: "divider", column_group_id: nil},
        %{type: "text", column_group_id: nil}
      ]

      assert {:error, _msg} = ContentTabHelpers.validate_column_group_blocks(blocks)
    end

    test "returns error for table blocks" do
      blocks = [
        %{type: "table", column_group_id: nil},
        %{type: "text", column_group_id: nil}
      ]

      assert {:error, _msg} = ContentTabHelpers.validate_column_group_blocks(blocks)
    end

    test "returns error for blocks already in column groups" do
      blocks = [
        %{type: "text", column_group_id: "g1"},
        %{type: "number", column_group_id: nil}
      ]

      assert {:error, _msg} = ContentTabHelpers.validate_column_group_blocks(blocks)
    end

    test "returns :ok for empty list" do
      assert ContentTabHelpers.validate_column_group_blocks([]) == :ok
    end
  end

  # ── enrich_with_references/2 ──────────────────────────────────────

  describe "enrich_with_references/2" do
    test "adds reference_target for reference-type blocks with a valid sheet target" do
      user = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      blocks = [
        %{
          id: 1,
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        }
      ]

      result = ContentTabHelpers.enrich_with_references(blocks, project.id)
      assert length(result) == 1
      enriched = hd(result)
      assert enriched.reference_target != nil
      assert enriched.reference_target.id == target_sheet.id
    end

    test "sets reference_target to nil for reference-type blocks with nil target" do
      user = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      blocks = [
        %{
          id: 1,
          type: "reference",
          value: %{"target_type" => nil, "target_id" => nil}
        }
      ]

      result = ContentTabHelpers.enrich_with_references(blocks, project.id)
      enriched = hd(result)
      assert enriched.reference_target == nil
    end

    test "sets reference_target to nil for non-reference blocks" do
      blocks = [
        %{id: 1, type: "text", value: %{}}
      ]

      result = ContentTabHelpers.enrich_with_references(blocks, 0)
      enriched = hd(result)
      assert enriched.reference_target == nil
    end
  end
end
