defmodule Storyarn.Flows.FlowRestoreIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.EntityReference

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{user: user, project: project}
  end

  test "restores the same flow and source identities and normalizes pending node data",
       %{project: project} do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})
    speaker = sheet_fixture(project, %{name: "Speaker"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{
          "referenced_flow_id" => target.id,
          "speaker_sheet_id" => speaker.id
        }
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert Repo.get!(FlowNode, source.id).data["referenced_flow_id"] == nil

    put_node_data(
      source.id,
      Map.put(Repo.get!(FlowNode, source.id).data, "speaker_sheet_id", to_string(speaker.id))
    )

    assert {:ok, restored_target} = Flows.restore_flow(deleted_target)

    restored_source = Repo.get!(FlowNode, source.id)
    assert restored_target.id == target.id
    assert restored_source.id == source.id
    assert restored_source.data["referenced_flow_id"] == target.id
    assert restored_source.data["speaker_sheet_id"] == speaker.id
    assert pending_flow_ref_count(target.id) == 0
  end

  test "preserves a pending reference when its same-project source flow is also in trash",
       %{project: project} do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert {:ok, deleted_host} = Flows.delete_flow(host)

    assert {:ok, restored_target} = Flows.restore_flow(deleted_target)
    assert restored_target.id == target.id
    assert Repo.get!(FlowNode, source.id).data["referenced_flow_id"] == target.id

    assert {:ok, restored_host} = Flows.restore_flow(deleted_host)
    assert restored_host.id == host.id
    assert Repo.get!(FlowNode, source.id).data["referenced_flow_id"] == target.id
  end

  test "rolls back when a pending reference no longer belongs to the source node type",
       %{project: project} do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    source.id
    |> then(&Repo.get!(FlowNode, &1))
    |> Ecto.Changeset.change(type: "annotation")
    |> Repo.update!()

    assert {:error, {:invalid_referenced_flow, "annotation", target_id}} =
             Flows.restore_flow(deleted_target)

    assert target_id == target.id
    assert_restore_rolled_back(target.id, source.id)
  end

  test "rolls back when another target in the pending source entered trash",
       %{project: project} do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})
    speaker = sheet_fixture(project, %{name: "Speaker"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{
          "referenced_flow_id" => target.id,
          "speaker_sheet_id" => speaker.id
        }
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert {:ok, _deleted_speaker} = Sheets.delete_sheet(speaker)

    put_node_data(
      source.id,
      Map.put(Repo.get!(FlowNode, source.id).data, "speaker_sheet_id", speaker.id)
    )

    assert {:error, {:invalid_project_reference, :speaker_sheet_id, speaker_id}} =
             Flows.restore_flow(deleted_target)

    assert speaker_id == speaker.id
    assert_restore_rolled_back(target.id, source.id)
    assert Repo.get!(FlowNode, source.id).data["speaker_sheet_id"] == speaker.id
  end

  test "does not reactivate an owned node while its referenced flow remains in trash",
       %{project: project} do
    target = flow_fixture(project, %{name: "Target"})
    referenced = flow_fixture(project, %{name: "Referenced"})

    owned_node =
      node_fixture(target, %{
        type: "subflow",
        data: %{"referenced_flow_id" => referenced.id}
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert {:ok, _deleted_reference} = Flows.delete_flow(referenced)
    assert Repo.get!(FlowNode, owned_node.id).data["referenced_flow_id"] == nil

    assert {:error, {:invalid_project_reference, :referenced_flow_id, referenced_id}} =
             Flows.restore_flow(deleted_target)

    assert referenced_id == referenced.id
    assert_deleted_flow(target.id)
    assert Repo.get!(FlowNode, owned_node.id).data["referenced_flow_id"] == nil
    assert pending_flow_ref_count(referenced.id) == 1
  end

  test "does not reactivate an owned node with a cross-project flow reference",
       %{user: user, project: project} do
    target = flow_fixture(project, %{name: "Target"})
    local_reference = flow_fixture(project, %{name: "Local reference"})

    owned_node =
      node_fixture(target, %{
        type: "subflow",
        data: %{"referenced_flow_id" => local_reference.id}
      })

    foreign_project = project_fixture(user)
    foreign_reference = flow_fixture(foreign_project, %{name: "Foreign reference"})

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    put_node_data(
      owned_node.id,
      Map.put(owned_node.data, "referenced_flow_id", foreign_reference.id)
    )

    assert {:error, {:invalid_project_reference, :referenced_flow_id, foreign_id}} =
             Flows.restore_flow(deleted_target)

    assert foreign_id == foreign_reference.id
    assert_deleted_flow(target.id)

    assert Repo.get!(FlowNode, owned_node.id).data["referenced_flow_id"] ==
             foreign_reference.id
  end

  test "rolls back a cross-project trash reference source", %{
    user: user,
    project: project
  } do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    foreign_project = project_fixture(user)
    foreign_flow = flow_fixture(foreign_project, %{name: "Foreign host"})

    foreign_source =
      node_fixture(foreign_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => nil}
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    ref =
      Repo.one!(
        from(ref in EntityTrashRef,
          where:
            ref.target_flow_id == ^target.id and
              ref.source_id == ^source.id
        )
      )

    ref
    |> Ecto.Changeset.change(source_id: foreign_source.id)
    |> Repo.update!()

    assert {:error, {:invalid_project_reference, :referenced_flow_id, target_id}} =
             Flows.restore_flow(deleted_target)

    assert target_id == target.id
    assert_deleted_flow(target.id)
    assert Repo.get!(FlowNode, foreign_source.id).data["referenced_flow_id"] == nil
    assert pending_flow_ref_count(target.id) == 1
  end

  test "never re-fetches a source inserted after source locking", %{
    user: user,
    project: project
  } do
    target = flow_fixture(project, %{name: "Target"})
    foreign_project = project_fixture(user)
    foreign_flow = flow_fixture(foreign_project, %{name: "Foreign source"})

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    [[missing_source_id]] =
      Repo.query!("SELECT nextval(pg_get_serial_sequence('flow_nodes', 'id'))").rows

    pending_ref =
      %EntityTrashRef{}
      |> EntityTrashRef.create_changeset(%{
        source_type: "flow_node",
        source_id: missing_source_id,
        source_field: "data.referenced_flow_id",
        target_flow_id: target.id
      })
      |> Repo.insert!()

    handler_id = "flow-restore-missing-source-race-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :flows, :flow_restore, :sources_locked],
        fn _event, _measurements, %{flow_id: restored_flow_id}, _config ->
          if restored_flow_id == target.id do
            Repo.insert!(%FlowNode{
              id: missing_source_id,
              flow_id: foreign_flow.id,
              type: "subflow",
              data: %{"referenced_flow_id" => nil}
            })
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, restored_target} = Flows.restore_flow(deleted_target)
    assert restored_target.id == target.id
    assert Repo.get!(FlowNode, missing_source_id).data["referenced_flow_id"] == nil
    refute Repo.get(EntityTrashRef, pending_ref.id)
  end

  test "rolls back when reinjection would introduce a flow-reference cycle",
       %{project: project} do
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    reverse =
      node_fixture(target, %{
        type: "annotation",
        data: %{"text" => "Will become a reverse reference"}
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    reverse
    |> Ecto.Changeset.change(
      type: "subflow",
      data: %{"referenced_flow_id" => host.id}
    )
    |> Repo.update!()

    assert {:error, :circular_reference} = Flows.restore_flow(deleted_target)
    assert_restore_rolled_back(target.id, source.id)
    assert Repo.get!(FlowNode, reverse.id).data["referenced_flow_id"] == host.id
  end

  test "rolls back when the restored flow parent entered trash",
       %{project: project} do
    parent = flow_fixture(project, %{name: "Parent"})
    target = flow_fixture(project, %{name: "Child", parent_id: parent.id})

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert {:ok, _deleted_parent} = Flows.delete_flow(parent)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.restore_flow(deleted_target)

    assert {"parent flow not found in project", _metadata} =
             changeset.errors[:parent_id]

    assert_deleted_flow(target.id)
  end

  test "rolls back when the restored flow scene entered trash",
       %{project: project} do
    scene = scene_fixture(project, %{name: "Scene"})
    target = flow_fixture(project, %{name: "Target", scene_id: scene.id})

    assert {:ok, deleted_target} = Flows.delete_flow(target)
    assert {:ok, _deleted_scene} = Scenes.delete_scene(scene)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.restore_flow(deleted_target)

    assert {"map not found in project", _metadata} =
             changeset.errors[:scene_id]

    assert_deleted_flow(target.id)
  end

  test "does not overwrite a shortcut that was reused while the flow was in trash",
       %{project: project} do
    target =
      flow_fixture(project, %{
        name: "Original",
        shortcut: "reusable-flow"
      })

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    replacement =
      flow_fixture(project, %{
        name: "Replacement",
        shortcut: "reusable-flow"
      })

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.restore_flow(deleted_target)

    assert {"is already taken in this project", _metadata} =
             changeset.errors[:shortcut]

    assert_deleted_flow(target.id)
    assert Repo.get!(Flow, replacement.id).deleted_at == nil
  end

  test "does not invent a missing response identity in an owned node",
       %{project: project} do
    target = flow_fixture(project, %{name: "Target"})

    dialogue =
      node_fixture(target, %{
        type: "dialogue",
        data: %{
          "text" => "Line",
          "responses" => [%{"text" => "Continue"}]
        }
      })

    response_id = hd(dialogue.data["responses"])["id"]

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    corrupted_data =
      Map.put(dialogue.data, "responses", [%{"text" => "Continue"}])

    put_node_data(dialogue.id, corrupted_data)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.restore_flow(deleted_target)

    assert {"every response must contain a valid id", _metadata} =
             changeset.errors[:data]

    assert is_binary(response_id)
    assert_deleted_flow(target.id)
    assert Repo.get!(FlowNode, dialogue.id).data == corrupted_data
  end

  test "preserves runtime ids and rebuilds entity and variable trackers for owned nodes",
       %{project: project} do
    target = flow_fixture(project, %{name: "Target"})
    speaker = sheet_fixture(project, %{name: "Speaker"})
    mentioned = sheet_fixture(project, %{name: "Mentioned"})
    stats = sheet_fixture(project, %{name: "Stats", shortcut: "game.stats"})

    block =
      block_fixture(stats, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    mention =
      ~s(<p><span class="mention" data-type="sheet" data-id="#{mentioned.id}">Mentioned</span></p>)

    dialogue =
      node_fixture(target, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => speaker.id,
          "text" => mention,
          "responses" => [%{"text" => "Continue"}]
        }
      })

    instruction =
      node_fixture(target, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => "assign_health",
              "sheet" => stats.shortcut,
              "variable" => block.variable_name,
              "operator" => "set",
              "value" => "100",
              "value_type" => "literal"
            }
          ]
        }
      })

    assert {:ok, dialogue, _meta} =
             Flows.update_node_data(dialogue, dialogue.data)

    assert {:ok, instruction, _meta} =
             Flows.update_node_data(instruction, instruction.data)

    localization_id = dialogue.data["localization_id"]
    response_ids = Enum.map(dialogue.data["responses"], & &1["id"])

    assert entity_targets(dialogue.id) == MapSet.new([speaker.id, mentioned.id])
    assert variable_target_ids(instruction.id) == MapSet.new([block.id])

    assert {:ok, deleted_target} = Flows.delete_flow(target)

    Repo.delete_all(
      from(reference in EntityReference,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^dialogue.id
      )
    )

    Repo.delete_all(
      from(reference in VariableReference,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^instruction.id
      )
    )

    assert entity_targets(dialogue.id) == MapSet.new()
    assert variable_target_ids(instruction.id) == MapSet.new()

    assert {:ok, restored_target} = Flows.restore_flow(deleted_target)
    assert restored_target.id == target.id

    restored_dialogue = Repo.get!(FlowNode, dialogue.id)
    assert restored_dialogue.data["localization_id"] == localization_id
    assert Enum.map(restored_dialogue.data["responses"], & &1["id"]) == response_ids
    assert entity_targets(dialogue.id) == MapSet.new([speaker.id, mentioned.id])
    assert variable_target_ids(instruction.id) == MapSet.new([block.id])
  end

  defp put_node_data(node_id, data) do
    node_id
    |> then(&Repo.get!(FlowNode, &1))
    |> Ecto.Changeset.change(data: data)
    |> Repo.update!()
  end

  defp pending_flow_ref_count(flow_id) do
    Repo.aggregate(
      from(ref in EntityTrashRef, where: ref.target_flow_id == ^flow_id),
      :count
    )
  end

  defp entity_targets(node_id) do
    from(reference in EntityReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id == ^node_id,
      select: reference.target_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp variable_target_ids(node_id) do
    from(reference in VariableReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id == ^node_id,
      select: reference.block_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp assert_restore_rolled_back(target_flow_id, source_node_id) do
    assert_deleted_flow(target_flow_id)
    assert Repo.get!(FlowNode, source_node_id).data["referenced_flow_id"] == nil
    assert pending_flow_ref_count(target_flow_id) == 1
  end

  defp assert_deleted_flow(flow_id) do
    flow = Repo.get!(Flow, flow_id)
    assert %DateTime{} = flow.deleted_at
    flow
  end
end
