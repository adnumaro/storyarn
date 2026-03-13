defmodule Storyarn.Drafts.QueryIsolationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Billing.Limits
  alias Storyarn.Drafts
  alias Storyarn.Flows
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.SheetQueries

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ScenesFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # Flow query isolation
  # ===========================================================================

  describe "flow query isolation" do
    test "draft flows are excluded from list_flows" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      flows = Flows.list_flows(project.id)
      # Only the original flow should appear
      assert length(flows) == 1
      assert hd(flows).id == flow.id
    end

    test "draft flows are excluded from list_flows_tree" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      tree = Flows.list_flows_tree(project.id)
      ids = Enum.map(tree, & &1.id)
      assert flow.id in ids
      # Should only have 1 flow (the original)
      assert length(ids) == 1
    end

    test "draft flows are excluded from search_flows" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project, %{name: "Unique Search Name"})

      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      results = Flows.search_flows(project.id, "Unique Search")
      assert length(results) == 1
      assert hd(results).id == flow.id
    end
  end

  # ===========================================================================
  # Sheet query isolation
  # ===========================================================================

  describe "sheet query isolation" do
    test "draft sheets are excluded from list_sheets_tree" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      {:ok, _draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)

      tree = Sheets.list_sheets_tree(project.id)
      ids = Enum.map(tree, & &1.id)
      assert sheet.id in ids
      assert length(ids) == 1
    end

    test "draft sheets are excluded from get_sheet" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      # Original should be findable
      assert Sheets.get_sheet(project.id, sheet.id) != nil

      # Draft entity should NOT be findable through normal queries
      assert Sheets.get_sheet(project.id, entity.id) == nil
    end

    test "draft sheets are excluded from search_sheets" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Unique Sheet Name"})

      {:ok, _draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)

      results = SheetQueries.search_sheets(project.id, "Unique Sheet")
      assert length(results) == 1
      assert hd(results).id == sheet.id
    end
  end

  # ===========================================================================
  # Scene query isolation
  # ===========================================================================

  describe "scene query isolation" do
    test "draft scenes are excluded from list_scenes" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)

      {:ok, _draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)

      scenes = Scenes.list_scenes(project.id)
      assert length(scenes) == 1
      assert hd(scenes).id == scene.id
    end

    test "draft scenes are excluded from get_scene" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert Scenes.get_scene(project.id, scene.id) != nil
      assert Scenes.get_scene(project.id, entity.id) == nil
    end

    test "draft scenes are excluded from search_scenes" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project, %{name: "Unique Scene Name"})

      {:ok, _draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)

      results = Scenes.search_scenes(project.id, "Unique Scene")
      assert length(results) == 1
      assert hd(results).id == scene.id
    end
  end

  # ===========================================================================
  # Billing isolation
  # ===========================================================================

  describe "billing count isolation" do
    test "count_project_items excludes draft entities" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)
      sheet = sheet_fixture(project)

      items_before = Limits.count_project_items(project.id)

      {:ok, _} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, _} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)

      items_after = Limits.count_project_items(project.id)

      assert items_after == items_before
    end
  end
end
