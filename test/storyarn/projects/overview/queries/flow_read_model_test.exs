defmodule Storyarn.Projects.FlowReadModelTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.FlowImportPersistence
  alias Storyarn.Projects.FlowReadModel

  setup do
    project = project_fixture(user_fixture())
    %{project: project}
  end

  describe "list_flows_for_export/2" do
    test "loads active Flows with nodes, sequence configs and connections", %{project: project} do
      flow = flow_fixture(project, %{name: "Exported"})
      assert {:ok, sequence} = Flows.create_sequence(flow.id, %{name: "Act I"})

      [exported] = FlowReadModel.list_flows_for_export(project.id)

      assert exported.id == flow.id
      assert is_list(exported.nodes)
      assert is_list(exported.connections)
      assert Enum.find(exported.nodes, &(&1.id == sequence.id)).sequence_config.name == "Act I"
    end

    test "filters the caller-owned export selection", %{project: project} do
      selected = flow_fixture(project, %{name: "Selected"})
      _excluded = flow_fixture(project, %{name: "Excluded"})

      assert [%{id: selected_id}] =
               FlowReadModel.list_flows_for_export(project.id, filter_ids: [selected.id])

      assert selected_id == selected.id
    end

    test "excludes soft-deleted Flows", %{project: project} do
      flow = flow_fixture(project)
      assert {:ok, _deleted} = Flows.delete_flow(flow)

      assert FlowReadModel.list_flows_for_export(project.id) == []
    end
  end

  describe "Project-owned Flow projections" do
    test "lists active shortcuts", %{project: project} do
      active = flow_fixture(project, %{name: "Active", shortcut: "active"})
      deleted = flow_fixture(project, %{name: "Deleted", shortcut: "deleted"})
      assert {:ok, _deleted} = Flows.delete_flow(deleted)

      assert FlowReadModel.list_shortcuts(project.id) == MapSet.new([active.shortcut])
    end

    test "returns only safely representable speaker sheet IDs", %{project: project} do
      speaker = sheet_fixture(project)
      flow = import_flow!(project)

      for speaker_id <- [
            speaker.id,
            "000#{speaker.id}",
            "9223372036854775807",
            "",
            "legacy-id",
            "9223372036854775808"
          ] do
        assert {:ok, _node} =
                 FlowImportPersistence.import_node(flow.id, %{
                   type: "dialogue",
                   data: %{"text" => "Line", "speaker_sheet_id" => speaker_id}
                 })
      end

      assert FlowReadModel.list_speaker_sheet_ids(project.id) ==
               MapSet.new([speaker.id, 9_223_372_036_854_775_807])
    end
  end

  defp import_flow!(project) do
    unique = System.unique_integer([:positive])

    {:ok, flow} =
      FlowImportPersistence.import_flow(project.id, %{
        name: "Imported Flow #{unique}",
        shortcut: "imported-flow-#{unique}"
      })

    flow
  end
end
