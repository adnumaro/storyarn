defmodule Storyarn.Exports.DataCollectorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # ===========================================================================
  # Setup
  # ===========================================================================

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # collect/2
  # ===========================================================================

  describe "collect/2" do
    setup [:setup_project]

    test "returns all sections for default options", %{project: project} do
      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts)

      assert data.project.id == project.id
      assert is_list(data.sheets)
      assert is_list(data.flows)
      assert is_list(data.scenes)
      assert is_list(data.screenplays)
      assert is_map(data.localization)
      assert is_list(data.assets)
    end

    test "returns empty lists for empty project", %{project: project} do
      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts)

      assert data.sheets == []
      assert data.flows == []
      assert data.scenes == []
      assert data.screenplays == []
      assert data.localization.languages == []
      assert data.assets == []
    end

    test "excludes sheets when include_sheets is false", %{project: project} do
      sheet_fixture(project, %{name: "Test Sheet"})

      opts = %ExportOptions{format: :storyarn, include_sheets: false}
      data = DataCollector.collect(project.id, opts)

      assert data.sheets == []
    end

    test "excludes flows when include_flows is false", %{project: project} do
      flow_fixture(project, %{name: "Test Flow"})

      opts = %ExportOptions{format: :storyarn, include_flows: false}
      data = DataCollector.collect(project.id, opts)

      assert data.flows == []
    end

    test "loads sheets with block preloads", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})

      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts)

      assert length(data.sheets) == 1
      loaded_sheet = hd(data.sheets)
      assert length(loaded_sheet.blocks) == 1
    end

    test "loads flows with nodes and connections preloaded", %{project: project} do
      flow = flow_fixture(project, %{name: "Test Flow"})
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      exit_node = node_fixture(flow, %{type: "exit", data: %{}})

      # Get the auto-created entry node
      entry = Enum.find(Storyarn.Flows.list_nodes(flow.id), &(&1.type == "entry"))
      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_node)

      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts)

      assert length(data.flows) == 1
      loaded_flow = hd(data.flows)
      # entry + dialogue + exit = 3 nodes
      assert length(loaded_flow.nodes) >= 3
      assert length(loaded_flow.connections) == 2
    end

    test "excludes soft-deleted entities", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Active Sheet"})
      deleted_sheet = sheet_fixture(project, %{name: "Deleted Sheet"})
      Storyarn.Sheets.delete_sheet(deleted_sheet)

      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts)

      sheet_ids = Enum.map(data.sheets, & &1.id)
      assert sheet.id in sheet_ids
      refute deleted_sheet.id in sheet_ids
    end
  end

  # ===========================================================================
  # Error paths
  # ===========================================================================

  describe "error paths" do
    test "collect with non-existent project_id raises" do
      opts = %ExportOptions{format: :storyarn}

      assert_raise Ecto.NoResultsError, fn ->
        DataCollector.collect(-1, opts)
      end
    end

    test "count_entities with non-existent project_id returns zeroes" do
      opts = %ExportOptions{format: :storyarn}
      counts = DataCollector.count_entities(-1, opts)

      assert counts.sheets == 0
      assert counts.flows == 0
      assert counts.nodes == 0
      assert counts.scenes == 0
      assert counts.screenplays == 0
      assert counts.assets == 0
    end

    test "collect excludes all sections when all flags are false" do
      user = user_fixture()
      project = project_fixture(user)
      sheet_fixture(project, %{name: "Sheet"})
      flow_fixture(project, %{name: "Flow"})

      opts = %ExportOptions{
        format: :storyarn,
        include_sheets: false,
        include_flows: false,
        include_scenes: false,
        include_screenplays: false,
        include_localization: false,
        include_assets: false
      }

      data = DataCollector.collect(project.id, opts)

      assert data.sheets == []
      assert data.flows == []
      assert data.scenes == []
      assert data.screenplays == []
      assert data.assets == []
    end
  end

  # ===========================================================================
  # collect/3 with preloaded data
  # ===========================================================================

  describe "collect/3 with preloaded data" do
    setup [:setup_project]

    test "uses preloaded flows instead of querying", %{project: project} do
      flow_fixture(project, %{name: "Real Flow"})

      fake_flows = [%{id: 999, name: "Preloaded Flow"}]
      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts, %{flows: fake_flows})

      # Should use the preloaded fake flows, not query the DB
      assert data.flows == fake_flows
    end

    test "falls back to DB query when section not in preloaded", %{project: project} do
      flow_fixture(project, %{name: "DB Flow"})

      opts = %ExportOptions{format: :storyarn}
      data = DataCollector.collect(project.id, opts, %{})

      assert length(data.flows) == 1
      assert hd(data.flows).name == "DB Flow"
    end
  end

  # ===========================================================================
  # count_entities/2
  # ===========================================================================

  describe "count_entities/2" do
    setup [:setup_project]

    test "returns zero counts for empty project", %{project: project} do
      opts = %ExportOptions{format: :storyarn}
      counts = DataCollector.count_entities(project.id, opts)

      assert counts.sheets == 0
      assert counts.flows == 0
      assert counts.nodes == 0
      assert counts.scenes == 0
      assert counts.screenplays == 0
      assert counts.assets == 0
    end

    test "counts sheets and flows correctly", %{project: project} do
      sheet_fixture(project, %{name: "S1"})
      sheet_fixture(project, %{name: "S2"})
      flow = flow_fixture(project, %{name: "F1"})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "test"}})

      opts = %ExportOptions{format: :storyarn}
      counts = DataCollector.count_entities(project.id, opts)

      assert counts.sheets == 2
      assert counts.flows == 1
      # entry (auto-created) + dialogue = 2
      assert counts.nodes >= 2
    end

    test "respects include flags", %{project: project} do
      sheet_fixture(project, %{name: "S1"})

      opts = %ExportOptions{format: :storyarn, include_sheets: false}
      counts = DataCollector.count_entities(project.id, opts)

      assert counts.sheets == 0
    end

    test "returns zero for disabled flows, scenes, and screenplays", %{project: project} do
      flow_fixture(project, %{name: "F1"})

      opts = %ExportOptions{
        format: :storyarn,
        include_flows: false,
        include_scenes: false,
        include_screenplays: false
      }

      counts = DataCollector.count_entities(project.id, opts)

      assert counts.flows == 0
      assert counts.scenes == 0
      assert counts.screenplays == 0
    end
  end

  # ===========================================================================
  # collect/3 with specific language filtering
  # ===========================================================================

  describe "collect/3 with language filtering" do
    setup [:setup_project]

    test "filters localization by specific language codes", %{project: project} do
      # When languages is a list of codes (not :all), it uses that list
      opts = %ExportOptions{format: :storyarn, languages: ["en", "es"]}
      data = DataCollector.collect(project.id, opts)

      assert is_map(data.localization)
      assert is_list(data.localization.languages)
      assert is_list(data.localization.strings)
    end
  end
end
