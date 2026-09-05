defmodule Storyarn.Projects.FlowReadModelTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.FlowImportPersistence
  alias Storyarn.Projects.FlowReadModel

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  describe "list_flows_for_export/2" do
    test "loads active Flows with nodes, sequence composition and connections", %{
      project: project,
      user: user
    } do
      flow = flow_fixture(project, %{name: "Exported"})
      assert {:ok, sequence} = Flows.create_sequence(flow.id, %{name: "Act I"})
      image = image_asset_fixture(project, user)

      assert {:ok, track} = Flows.upsert_sequence_track(sequence.id, "music", %{})

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop"
               })

      [exported] = FlowReadModel.list_flows_for_export(project.id)

      assert exported.id == flow.id
      assert is_list(exported.nodes)
      assert is_list(exported.connections)

      exported_sequence = Enum.find(exported.nodes, &(&1.id == sequence.id))
      assert exported_sequence.sequence_config.name == "Act I"
      assert Enum.map(exported_sequence.sequence_tracks, & &1.id) == [track.id]
      assert Enum.map(exported_sequence.sequence_visual_layers, & &1.id) == [layer.id]
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
