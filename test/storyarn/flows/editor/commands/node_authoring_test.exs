defmodule Storyarn.Flows.NodeAuthoringTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.Editor, as: Flows

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project, %{shortcut: "intro"})

    %{flow: flow, project: project}
  end

  test "create without data applies the Flow-owned defaults", %{flow: flow} do
    assert {:ok, node} = Flows.create_node(flow, %{type: "dialogue"})

    assert node.data["text"] == ""
    assert node.data["speaker_sheet_id"] == nil
    assert node.data["responses"] == []
    assert is_binary(node.data["localization_id"])
  end

  test "merge_form accepts only fields owned by the node type and normalizes empty IDs", %{
    flow: flow
  } do
    node = node_fixture(flow, %{type: "dialogue"})

    assert {:ok, result} =
             Flows.edit_node(flow.id, node.id, :merge_form, %{
               params: %{
                 "text" => "Hello",
                 "speaker_sheet_id" => "",
                 "audio_asset_id" => "",
                 "foreign_payload" => "must not persist"
               }
             })

    assert result.current_data["text"] == "Hello"
    assert result.current_data["speaker_sheet_id"] == nil
    assert result.current_data["audio_asset_id"] == nil
    refute Map.has_key?(result.current_data, "foreign_payload")
  end

  test "put_field rejects a field outside the node vocabulary", %{flow: flow} do
    node = node_fixture(flow, %{type: "annotation"})

    assert {:error, :field_not_editable} =
             Flows.edit_node(flow.id, node.id, :put_field, %{
               field: "audio_asset_id",
               value: 42
             })

    refute Map.has_key?(Flows.get_node!(flow.id, node.id).data, "audio_asset_id")
  end

  test "concurrent edits to distinct fields compose from the locked row", %{flow: flow} do
    node = node_fixture(flow, %{type: "dialogue"})
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(
        [
          {"text", "First line"},
          {"stage_directions", "[whispers]"}
        ],
        fn {field, value} ->
          Task.async(fn ->
            send(parent, {barrier, :ready, self()})

            receive do
              {^barrier, :go} ->
                Flows.edit_node(flow.id, node.id, :put_field, %{field: field, value: value})
            end
          end)
        end
      )

    task_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {^barrier, :ready, pid}
        pid
      end)

    Enum.each(task_pids, &send(&1, {barrier, :go}))
    assert Enum.all?(Enum.map(tasks, &Task.await(&1, 5_000)), &match?({:ok, _result}, &1))

    persisted = Flows.get_node!(flow.id, node.id)
    assert persisted.data["text"] == "First line"
    assert persisted.data["stage_directions"] == "[whispers]"
  end

  test "reference validation and technical ID generation execute inside the locked command", %{
    flow: flow,
    project: project
  } do
    target_flow = flow_fixture(project, %{name: "Target"})
    subflow = node_fixture(flow, %{type: "subflow"})
    speaker = sheet_fixture(project, %{name: "Lady Ada"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => speaker.id, "text" => "Welcome"}
      })

    assert {:ok, reference_result} =
             Flows.edit_node(flow.id, subflow.id, :put_subflow_reference, %{
               value: target_flow.id
             })

    assert reference_result.current_data["referenced_flow_id"] == target_flow.id

    assert {:error, :self_reference} =
             Flows.edit_node(flow.id, subflow.id, :put_subflow_reference, %{value: flow.id})

    assert Flows.get_node!(flow.id, subflow.id).data["referenced_flow_id"] == target_flow.id

    assert {:ok, technical_id_result} =
             Flows.edit_node(flow.id, dialogue.id, :generate_technical_id, %{})

    assert technical_id_result.current_data["technical_id"] =~ ~r/\Aintro_lady_ada_\d+\z/
  end

  test "delete reports graph refresh semantics without exposing sequence trigger behavior", %{
    flow: flow
  } do
    assert {:ok, sequence} =
             Flows.create_sequence(flow.id, %{
               "name" => "Nested beat",
               "position_x" => 10,
               "position_y" => 20
             })

    assert {:ok, _deleted, meta} = Flows.delete_node(sequence)
    assert meta.graph_changed?
    assert meta.refresh_scope == :flow
  end

  test "single-node canvas projections are owned by Flows for nodes and sequences", %{
    flow: flow
  } do
    assert {:ok, sequence} =
             Flows.create_sequence(flow.id, %{
               "name" => "Opening beat",
               "position_x" => 40,
               "position_y" => 80
             })

    dialogue = node_fixture(flow, %{type: "dialogue", parent_id: sequence.id})
    dialogue_id = dialogue.id
    dialogue_x = dialogue.position_x
    dialogue_y = dialogue.position_y
    sequence_id = sequence.id

    assert %{
             id: ^dialogue_id,
             type: "dialogue",
             parent_id: ^sequence_id,
             position: %{x: ^dialogue_x, y: ^dialogue_y},
             data: dialogue_data
           } = Flows.serialize_editor_node(dialogue, flow.project_id)

    assert dialogue_data["localization_id"] == dialogue.data["localization_id"]

    assert %{
             id: ^sequence_id,
             type: "sequence",
             parent_id: nil,
             position: %{x: 40.0, y: 80.0},
             data: %{
               "name" => "Opening beat",
               "width" => 300.0,
               "height" => 200.0
             }
           } = Flows.serialize_editor_node(sequence, flow.project_id)
  end

  test "restore returns only active connections in its Flow-owned graph fragment", %{flow: flow} do
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    dialogue = node_fixture(flow, %{type: "dialogue"})

    assert {:ok, connection} =
             Flows.create_connection(flow, entry, dialogue, %{
               source_pin: "output",
               target_pin: "input"
             })

    assert {:ok, _deleted, _meta} = Flows.delete_node(dialogue)

    assert {:ok, %{node: restored_node, connections: connections}} =
             Flows.restore_editor_node(flow, dialogue.id)

    assert restored_node.id == dialogue.id
    assert Enum.map(connections, & &1.id) == [connection.id]
  end

  test "restore_data accepts the serialized node id used by the LiveView adapter", %{flow: flow} do
    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Original", "speaker_sheet_id" => nil}
      })

    assert {:ok, _updated, _meta} =
             Flows.update_node_data(node, %{"text" => "Modified", "speaker_sheet_id" => nil})

    localization_id = Flows.get_node!(flow.id, node.id).data["localization_id"]

    assert {:ok, result} =
             Flows.edit_node(flow.id, Integer.to_string(node.id), :restore_data, %{
               data: %{"text" => "Original", "speaker_sheet_id" => nil}
             })

    assert result.current_data["text"] == "Original"
    assert result.current_data["localization_id"] == localization_id
    assert Flows.get_node!(flow.id, node.id).data["text"] == "Original"
  end
end
