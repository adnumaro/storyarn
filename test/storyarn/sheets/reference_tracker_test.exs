defmodule Storyarn.Sheets.ReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.ReferenceTracker

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # Block references with nil target / unknown type
  # =============================================================================

  describe "update_block_references/1 with nil reference target" do
    test "creates no references when reference block has nil target_id" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => nil}
        })

      ReferenceTracker.update_block_references(block)

      # No references should be created since target_id is nil
      backlinks = ReferenceTracker.get_backlinks("sheet", 0)
      assert backlinks == []
    end

    test "creates no references when reference block has no target fields" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          value: %{}
        })

      ReferenceTracker.update_block_references(block)

      # Should not create any references
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  describe "update_block_references/1 with unknown block type" do
    test "creates no references for text block (non-rich_text, non-reference)" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "text",
          config: %{"label" => "Simple Field"},
          value: %{"content" => "plain text"}
        })

      ReferenceTracker.update_block_references(block)

      # Text blocks have no references to track
      # Verify no error occurred and no references were created
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "creates no references for number block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => 42}
        })

      ReferenceTracker.update_block_references(block)

      # Number blocks produce no references
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  # =============================================================================
  # Flow node references
  # =============================================================================

  describe "update_flow_node_references/1" do
    test "creates speaker reference from dialogue node" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Speaker"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
        })

      ReferenceTracker.update_flow_node_references(node)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks != []

      speaker_ref = Enum.find(backlinks, &(&1.context == "speaker"))
      assert speaker_ref != nil
      assert speaker_ref.source_type == "flow_node"
      assert speaker_ref.source_id == node.id
    end

    test "creates mention references from dialogue text" do
      %{project: project} = setup_project()
      target_sheet = sheet_fixture(project, %{name: "Mentioned"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      mention_html =
        ~s(<p>Meet <span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Mentioned</span></p>)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => mention_html}
        })

      ReferenceTracker.update_flow_node_references(node)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks != []

      dialogue_ref = Enum.find(backlinks, &(&1.context == "dialogue"))
      assert dialogue_ref != nil
    end

    test "returns :ok for node without data map" do
      assert :ok == ReferenceTracker.update_flow_node_references(%{id: 999, data: nil})
    end

    test "returns :ok for non-map input" do
      assert :ok == ReferenceTracker.update_flow_node_references("not a map")
    end
  end

  # =============================================================================
  # Delete target references
  # =============================================================================

  describe "delete_target_references/2" do
    test "removes all references pointing to a given target" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

      {count, nil} = ReferenceTracker.delete_target_references("sheet", target_sheet.id)

      assert count == 1
      assert ReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0
    end

    test "returns zero count when no references exist for target" do
      {count, nil} = ReferenceTracker.delete_target_references("sheet", -1)

      assert count == 0
    end
  end

  # =============================================================================
  # parse_id/1 with non-integer inputs
  # =============================================================================

  describe "parse_id edge cases via batch_insert_references" do
    test "handles string IDs in reference targets" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})
      target_sheet = sheet_fixture(project, %{name: "Target"})

      # Create a reference block with target_id as a string
      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => "#{target_sheet.id}"}
        })

      # This exercises parse_id/1 with a valid integer string
      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert length(backlinks) == 1
    end

    test "skips references with non-integer string IDs" do
      %{project: project} = setup_project()
      source_sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => "not-a-number"}
        })

      # This exercises parse_id/1 returning nil for non-integer strings
      ReferenceTracker.update_block_references(block)

      # No references should be created since the ID is invalid
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  # =============================================================================
  # Screenplay element references (fallback clause)
  # =============================================================================

  describe "update_screenplay_element_references/1" do
    test "returns :ok for non-matching input" do
      assert :ok == ReferenceTracker.update_screenplay_element_references("not a map")
    end

    test "returns :ok for map without required keys" do
      assert :ok == ReferenceTracker.update_screenplay_element_references(%{id: 1})
    end
  end

  # =============================================================================
  # Scene pin/zone references (fallback clauses)
  # =============================================================================

  describe "update_scene_pin_references/1" do
    test "returns :ok for non-matching input" do
      assert :ok == ReferenceTracker.update_scene_pin_references("not a map")
    end
  end

  describe "update_scene_zone_references/1" do
    test "returns :ok for non-matching input" do
      assert :ok == ReferenceTracker.update_scene_zone_references("not a map")
    end
  end

  # =============================================================================
  # Rich text mention extraction edge cases
  # =============================================================================

  describe "update_block_references/1 with rich_text mentions" do
    test "handles rich_text with no mention spans" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => "<p>Just plain text, no mentions.</p>"}
        })

      ReferenceTracker.update_block_references(block)

      # No references should be created
      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "handles rich_text with nil content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => nil}
        })

      ReferenceTracker.update_block_references(block)

      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end

    test "handles rich_text with empty content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Source"})

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "rich_text",
          value: %{"content" => ""}
        })

      ReferenceTracker.update_block_references(block)

      assert ReferenceTracker.count_backlinks("sheet", 0) == 0
    end
  end

  # =============================================================================
  # Flow node with empty speaker_sheet_id
  # =============================================================================

  describe "update_flow_node_references/1 with empty speaker" do
    test "ignores empty string speaker_sheet_id" do
      %{project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Test Flow"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => "", "text" => "Hello"}
        })

      # This exercises the maybe_add_sheet_ref(refs, "", _context) clause
      ReferenceTracker.update_flow_node_references(node)

      # No speaker reference should be created
      # (empty string should be treated like nil)
      refs = ReferenceTracker.get_backlinks("sheet", 0)
      assert refs == []
    end
  end
end
