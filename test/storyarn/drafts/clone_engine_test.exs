defmodule Storyarn.Drafts.CloneEngineTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Drafts
  alias Storyarn.Flows
  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 4]
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ScenesFixtures, except: [connection_fixture: 4]

  alias Storyarn.FlowsFixtures
  alias Storyarn.ScenesFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # Flow cloning
  # ===========================================================================

  describe "clone flow" do
    test "clones flow with nodes" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      _node1 = node_fixture(flow, %{type: "dialogue"})
      _node2 = node_fixture(flow, %{type: "hub"})

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity.id != flow.id
      assert entity.draft_id == draft.id
      assert entity.project_id == project.id

      # Check nodes were cloned
      cloned_nodes = Flows.list_nodes(entity.id)
      original_nodes = Flows.list_nodes(flow.id)
      assert length(cloned_nodes) == length(original_nodes)

      # IDs should differ
      cloned_ids = MapSet.new(cloned_nodes, & &1.id)
      original_ids = MapSet.new(original_nodes, & &1.id)
      assert MapSet.disjoint?(cloned_ids, original_ids)
    end

    test "clones flow with connections remapped" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      node1 = node_fixture(flow, %{type: "dialogue"})
      node2 = node_fixture(flow, %{type: "dialogue"})
      _conn = FlowsFixtures.connection_fixture(flow, node1, node2)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      cloned_connections = Flows.list_connections(entity.id)
      assert length(cloned_connections) == 1

      cloned_conn = hd(cloned_connections)
      # Connection should reference cloned node IDs, not originals
      assert cloned_conn.source_node_id != node1.id
      assert cloned_conn.target_node_id != node2.id
    end

    test "preserves external references in flow nodes" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => sheet.id, "text" => "Hello"}
        })

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      cloned_nodes = Flows.list_nodes(entity.id)
      dialogue = Enum.find(cloned_nodes, &(&1.type == "dialogue"))
      assert dialogue.data["speaker_sheet_id"] == sheet.id
    end

    test "cloned flow has nil shortcut" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity.shortcut == nil
    end

    test "cannot create draft from a draft entity" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      draft_entity = Drafts.get_draft_entity(draft)

      # Attempting to create a draft from the cloned entity should fail
      # because clone source queries filter is_nil(draft_id)
      assert {:error, _} = Drafts.create_draft(project.id, "flow", draft_entity.id, user.id)
    end
  end

  # ===========================================================================
  # Sheet cloning
  # ===========================================================================

  describe "clone sheet" do
    test "clones sheet with blocks" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      _block1 = block_fixture(sheet, %{type: "text"})
      _block2 = block_fixture(sheet, %{type: "number"})

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity.id != sheet.id
      assert entity.draft_id == draft.id

      cloned_blocks = Sheets.list_blocks(entity.id)
      original_blocks = Sheets.list_blocks(sheet.id)
      assert length(cloned_blocks) == length(original_blocks)
    end

    test "clones sheet with table data" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      table = table_block_fixture(sheet)
      _extra_col = table_column_fixture(table)
      _extra_row = table_row_fixture(table)

      # Re-preload to get the extra column/row
      original_table =
        Storyarn.Repo.preload(table, [:table_columns, :table_rows], force: true)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      cloned_blocks = Sheets.list_blocks(entity.id)
      cloned_table = Enum.find(cloned_blocks, &(&1.type == "table"))

      assert cloned_table != nil
      cloned_table = Storyarn.Repo.preload(cloned_table, [:table_columns, :table_rows])

      assert length(cloned_table.table_columns) == length(original_table.table_columns)
      assert length(cloned_table.table_rows) == length(original_table.table_rows)
    end
  end

  # ===========================================================================
  # Sheet cloning with inheritance
  # ===========================================================================

  describe "clone sheet with inheritance" do
    test "preserves inherited_from_block_id for cross-sheet inherited blocks" do
      %{user: user, project: project} = setup_project()

      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})

      parent_block = inheritable_block_fixture(parent, label: "Health")

      # Child should have an inherited instance pointing to parent block
      child_blocks = Sheets.list_blocks(child.id)
      inherited_block = Enum.find(child_blocks, &(not is_nil(&1.inherited_from_block_id)))
      assert inherited_block
      assert inherited_block.inherited_from_block_id == parent_block.id

      # Clone the child sheet as a draft
      {:ok, draft} = Drafts.create_draft(project.id, "sheet", child.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      cloned_blocks = Sheets.list_blocks(entity.id)
      assert length(cloned_blocks) == length(child_blocks)

      # Cloned blocks must preserve cross-sheet inherited_from_block_id
      # so inheritance stays intact when the draft is merged back
      cloned_inherited = Enum.find(cloned_blocks, &(not is_nil(&1.inherited_from_block_id)))
      assert cloned_inherited
      assert cloned_inherited.inherited_from_block_id == parent_block.id
    end
  end

  # ===========================================================================
  # Scene cloning
  # ===========================================================================

  describe "clone scene" do
    test "clones scene with layers, pins, and zones" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)
      _layer = layer_fixture(scene)
      _pin = pin_fixture(scene)
      _zone = zone_fixture(scene)

      {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity.id != scene.id
      assert entity.draft_id == draft.id

      # Scene is preloaded with children
      assert entity.layers != []
      assert [_] = entity.pins
      assert [_] = entity.zones
    end

    test "clones scene with connections remapped" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin A"})
      pin2 = pin_fixture(scene, %{"label" => "Pin B"})
      _conn = ScenesFixtures.connection_fixture(scene, pin1, pin2)

      {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert length(entity.connections) == 1
      cloned_conn = hd(entity.connections)
      # Should reference cloned pin IDs
      assert cloned_conn.from_pin_id != pin1.id
      assert cloned_conn.to_pin_id != pin2.id
    end
  end
end
