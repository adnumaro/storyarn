defmodule Storyarn.Flows.NodeRestoreIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.EntityReference

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  test "restores exact dialogue identities and rebuilds entity backlinks", %{
    project: project,
    flow: flow
  } do
    speaker = sheet_fixture(project, %{name: "Speaker", shortcut: "cast.speaker"})
    mentioned = sheet_fixture(project, %{name: "Mentioned", shortcut: "cast.mentioned"})
    {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Dialogue group"})

    localization_id = RuntimeKey.new_dialogue_id()
    response_ids = [RuntimeKey.new_response_id(), RuntimeKey.new_response_id()]

    text =
      ~s(<p><span class="mention" data-type="sheet" data-id="#{mentioned.id}">Mentioned</span></p>)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        parent_id: sequence.id,
        data: %{
          "localization_id" => localization_id,
          "speaker_sheet_id" => speaker.id,
          "text" => text,
          "responses" => [
            %{"id" => Enum.at(response_ids, 0), "text" => "First"},
            %{"id" => Enum.at(response_ids, 1), "text" => "Second"}
          ]
        }
      })

    assert {:ok, tracked_node, _meta} = Flows.update_node_data(node, node.data)
    assert backlink_targets(tracked_node.id) == MapSet.new([speaker.id, mentioned.id])

    assert {:ok, _deleted, _meta} = Flows.delete_node(tracked_node)
    assert backlink_targets(node.id) == MapSet.new()

    assert {:ok, restored} = Flows.restore_node(flow.id, node.id)

    assert restored.parent_id == sequence.id
    assert restored.data["localization_id"] == localization_id
    assert Enum.map(restored.data["responses"], & &1["id"]) == response_ids
    assert backlink_targets(restored.id) == MapSet.new([speaker.id, mentioned.id])

    assert Enum.any?(
             References.get_backlinks_with_sources("sheet", mentioned.id, project.id),
             &(&1.source_id == restored.id)
           )
  end

  test "rebuilds variable usages after restore", %{project: project, flow: flow} do
    sheet = sheet_fixture(project, %{name: "Stats", shortcut: "game.stats"})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    node =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => "assign_health",
              "sheet" => sheet.shortcut,
              "variable" => block.variable_name,
              "operator" => "set",
              "value" => "100",
              "value_type" => "literal"
            }
          ]
        }
      })

    assert {:ok, tracked_node, _meta} = Flows.update_node_data(node, node.data)
    assert Flows.count_variable_usage(block.id)["write"] == 1

    assert {:ok, _deleted, _meta} = Flows.delete_node(tracked_node)
    assert Flows.count_variable_usage(block.id) == %{}

    assert {:ok, restored} = Flows.restore_node(flow.id, node.id)
    assert Flows.count_variable_usage(block.id)["write"] == 1

    assert Repo.exists?(
             from(reference in VariableReference,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^restored.id and
                   reference.block_id == ^block.id and reference.kind == "write"
             )
           )
  end

  test "normalizes valid persisted reference ids while restoring", %{
    project: project,
    flow: flow
  } do
    target = flow_fixture(project, %{name: "Normalized target"})

    node =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    assert {:ok, _deleted, _meta} = Flows.delete_node(node)

    put_node_data(
      node.id,
      Map.put(node.data, "referenced_flow_id", to_string(target.id))
    )

    assert {:ok, restored} = Flows.restore_node(flow.id, node.id)
    assert restored.data["referenced_flow_id"] == target.id
  end

  test "does not restore a hub after its identity is reused", %{flow: flow} do
    first = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "shared_hub"}})
    assert {:ok, _deleted, _meta} = Flows.delete_node(first)

    second = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "shared_hub"}})

    assert {:error, :hub_id_not_unique} = Flows.restore_node(flow.id, first.id)
    assert_deleted(first.id)
    assert Repo.get!(FlowNode, second.id).deleted_at == nil
  end

  test "does not restore below a sequence that entered trash", %{flow: flow} do
    {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Parent"})
    child = node_fixture(flow, %{type: "dialogue", parent_id: sequence.id})

    assert {:ok, _deleted_child, _meta} = Flows.delete_node(child)
    assert {:ok, _deleted_sequence, _meta} = Flows.delete_node(sequence)
    put_node_parent(child.id, sequence.id)

    assert {:error, {:invalid_node_parent, parent_id}} =
             Flows.restore_node(flow.id, child.id)

    assert parent_id == sequence.id
    assert_deleted(child.id)
  end

  test "does not restore a subflow after its target flow entered trash", %{
    project: project,
    flow: flow
  } do
    target = flow_fixture(project, %{name: "Target flow"})

    node =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    assert {:ok, _deleted_node, _meta} = Flows.delete_node(node)
    assert {:ok, _deleted_target} = Flows.delete_flow(target)
    put_node_data(node.id, Map.put(node.data, "referenced_flow_id", target.id))

    assert {:error, {:invalid_project_reference, :referenced_flow_id, target_id}} =
             Flows.restore_node(flow.id, node.id)

    assert target_id == target.id
    assert_deleted(node.id)
  end

  test "does not restore a dialogue after its speaker entered trash", %{
    project: project,
    flow: flow
  } do
    speaker = sheet_fixture(project, %{name: "Temporary speaker"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => speaker.id,
          "text" => "Line",
          "responses" => []
        }
      })

    assert {:ok, _deleted_node, _meta} = Flows.delete_node(node)
    assert {:ok, _deleted_speaker} = Sheets.delete_sheet(speaker)

    assert {:error, {:invalid_project_reference, :speaker_sheet_id, speaker_id}} =
             Flows.restore_node(flow.id, node.id)

    assert speaker_id == speaker.id
    assert_deleted(node.id)
  end

  test "does not restore a jump after its target hub entered trash", %{flow: flow} do
    hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "target_hub"}})
    jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "target_hub"}})

    assert {:ok, _deleted_jump, _meta} = Flows.delete_node(jump)

    hub
    |> FlowNode.soft_delete_changeset()
    |> Repo.update!()

    assert {:error, {:invalid_jump_target, "target_hub"}} =
             Flows.restore_node(flow.id, jump.id)

    assert_deleted(jump.id)
  end

  test "does not restore a node with a cross-project audio asset", %{
    user: user,
    project: project,
    flow: flow
  } do
    local_audio = audio_asset_fixture(project, user)
    foreign_project = project_fixture(user)
    foreign_audio = audio_asset_fixture(foreign_project, user)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => local_audio.id, "text" => "Line", "responses" => []}
      })

    assert {:ok, _deleted, _meta} = Flows.delete_node(node)
    put_node_data(node.id, Map.put(node.data, "audio_asset_id", foreign_audio.id))

    assert {:error, {:invalid_project_reference, :audio_asset_id, asset_id}} =
             Flows.restore_node(flow.id, node.id)

    assert asset_id == foreign_audio.id
    assert_deleted(node.id)
  end

  test "does not restore malformed mentions", %{project: project, flow: flow} do
    mentioned = sheet_fixture(project, %{name: "Mention target"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => ~s(<p><span class="mention" data-type="sheet" data-id="#{mentioned.id}">Valid</span></p>),
          "responses" => []
        }
      })

    assert {:ok, _deleted, _meta} = Flows.delete_node(node)

    malformed =
      Map.put(
        node.data,
        "text",
        ~s(<p><span class="mention" data-type="sheet">Missing ID</span></p>)
      )

    put_node_data(node.id, malformed)

    assert {:error, {:invalid_project_reference, {:flow_node_mention, :malformed}, %{id: [], type: ["sheet"]}}} =
             Flows.restore_node(flow.id, node.id)

    assert_deleted(node.id)
  end

  test "does not invent a missing response identity while restoring", %{flow: flow} do
    localization_id = RuntimeKey.new_dialogue_id()
    response_id = RuntimeKey.new_response_id()

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "localization_id" => localization_id,
          "text" => "Line",
          "responses" => [%{"id" => response_id, "text" => "Continue"}]
        }
      })

    assert {:ok, _deleted, _meta} = Flows.delete_node(node)

    corrupted_data =
      Map.put(node.data, "responses", [%{"text" => "Continue"}])

    put_node_data(node.id, corrupted_data)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.restore_node(flow.id, node.id)

    assert {"every response must contain a valid id", _metadata} =
             changeset.errors[:data]

    persisted = assert_deleted(node.id)
    assert persisted.data["localization_id"] == localization_id
    assert persisted.data["responses"] == [%{"text" => "Continue"}]
  end

  defp backlink_targets(node_id) do
    from(reference in EntityReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id == ^node_id,
      select: reference.target_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp put_node_data(node_id, data) do
    node_id
    |> then(&Repo.get!(FlowNode, &1))
    |> Ecto.Changeset.change(data: data)
    |> Repo.update!()
  end

  defp put_node_parent(node_id, parent_id) do
    node_id
    |> then(&Repo.get!(FlowNode, &1))
    |> Ecto.Changeset.change(parent_id: parent_id)
    |> Repo.update!()
  end

  defp assert_deleted(node_id) do
    node = Repo.get!(FlowNode, node_id)
    assert %DateTime{} = node.deleted_at
    node
  end
end
