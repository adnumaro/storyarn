defmodule Storyarn.Versioning.ProjectSnapshotReferenceIndexIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References
  alias Storyarn.References.EntityReference
  alias Storyarn.References.VariableReference
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  test "project restore preserves entity and variable indexes owned by preexisting trash roots" do
    user = user_fixture()
    project = project_fixture(user)

    target_sheet =
      sheet_fixture(project, %{
        name: "Referenced character",
        shortcut: "characters.referenced"
      })

    target_variable =
      block_fixture(target_sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    source_sheet = sheet_fixture(project, %{name: "Trash sheet source"})

    source_block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{
          "target_type" => "sheet",
          "target_id" => target_sheet.id
        }
      })

    source_flow = flow_fixture(project, %{name: "Trash flow source"})

    dialogue =
      node_fixture(source_flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => target_sheet.id,
          "text" => "Reference from a deleted flow"
        }
      })

    instruction =
      node_fixture(source_flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            variable_assignment(
              target_sheet.shortcut,
              target_variable.variable_name
            )
          ]
        }
      })

    assert :ok =
             References.update_flow_node_entity_references(
               dialogue,
               project_id: project.id
             )

    assert :ok =
             References.update_flow_node_variable_references(instruction)

    source_scene = scene_fixture(project, %{name: "Trash scene source"})
    target_scene = scene_fixture(project, %{name: "Referenced scene"})

    source_pin =
      pin_fixture(source_scene, %{
        "sheet_id" => target_sheet.id,
        "condition" =>
          variable_condition(
            target_sheet.shortcut,
            target_variable.variable_name
          )
      })

    source_zone =
      zone_fixture(source_scene, %{
        "target_type" => "scene",
        "target_id" => target_scene.id,
        "condition" =>
          variable_condition(
            target_sheet.shortcut,
            target_variable.variable_name
          )
      })

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               :ok =
                 References.update_scene_zone_entity_references(
                   source_zone,
                   project_id: project.id
                 )

               :ok =
                 References.update_scene_zone_variable_references(
                   source_zone,
                   project_id: project.id
                 )
             end)

    entity_sources = [
      {"block", source_block.id},
      {"flow_node", dialogue.id},
      {"scene_pin", source_pin.id},
      {"scene_zone", source_zone.id}
    ]

    variable_sources = [
      {"flow_node", instruction.id},
      {"scene_pin", source_pin.id},
      {"scene_zone", source_zone.id}
    ]

    assert {:ok, _deleted_sheet} = Sheets.delete_sheet(source_sheet)
    assert {:ok, _deleted_flow} = Flows.delete_flow(source_flow)
    assert {:ok, _deleted_scene} = Scenes.delete_scene(source_scene)

    entity_before = reference_state(EntityReference, entity_sources)
    variable_before = reference_state(VariableReference, variable_sources)

    assert length(entity_before) == 4
    assert length(variable_before) == 3

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

    assert reference_state(EntityReference, entity_sources) == entity_before
    assert reference_state(VariableReference, variable_sources) == variable_before

    assert {:ok, _restored_scene} = Scenes.restore_scene(source_scene)

    assert Enum.any?(
             References.get_backlinks_with_sources(
               "sheet",
               target_sheet.id,
               project.id
             ),
             &(&1.source_type == "scene_pin" and
                 &1.source_id == source_pin.id)
           )

    assert Enum.any?(
             References.get_backlinks_with_sources(
               "scene",
               target_scene.id,
               project.id
             ),
             &(&1.source_type == "scene_zone" and
                 &1.source_id == source_zone.id)
           )
  end

  test "moving a current-only Flow to trash sweeps inbound refs and remains reversible" do
    user = user_fixture()
    project = project_fixture(user)
    caller_flow = flow_fixture(project, %{name: "Snapshot caller"})
    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    removed_flow = flow_fixture(project, %{name: "Current-only target"})

    source_node =
      node_fixture(caller_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => removed_flow.id}
      })

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert %FlowNode{data: %{"referenced_flow_id" => nil}} =
             Repo.get!(FlowNode, source_node.id)

    assert %Flow{deleted_at: %DateTime{}} =
             Repo.get!(Flow, removed_flow.id)

    assert Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^source_node.id and
                   reference.source_field == "data.referenced_flow_id" and
                   reference.target_flow_id == ^removed_flow.id
             )
           )

    current_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               safety_snapshot,
               pre_restore_snapshot: current_snapshot
             )

    assert %Flow{deleted_at: nil} = Repo.get!(Flow, removed_flow.id)

    assert %FlowNode{deleted_at: nil} =
             restored_source = Repo.get!(FlowNode, source_node.id)

    assert restored_source.data["referenced_flow_id"] == removed_flow.id

    refute Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^source_node.id and
                   reference.source_field == "data.referenced_flow_id" and
                   reference.target_flow_id == ^removed_flow.id
             )
           )
  end

  test "target snapshot node data wins over a pending Flow trash reference" do
    user = user_fixture()
    project = project_fixture(user)
    target_flow = flow_fixture(project, %{name: "Restored target"})
    caller_flow = flow_fixture(project, %{name: "Authoritative caller"})
    source_node = node_fixture(caller_flow, %{type: "subflow", data: %{}})
    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _updated_node, _meta} =
             Flows.update_node_data(
               source_node,
               %{"referenced_flow_id" => target_flow.id}
             )

    assert {:ok, _deleted_flow} = Flows.delete_flow(target_flow)

    assert Repo.get!(FlowNode, source_node.id).data["referenced_flow_id"] ==
             nil

    assert Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_id == ^source_node.id and
                   reference.target_flow_id == ^target_flow.id
             )
           )

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert %Flow{deleted_at: nil} = Repo.get!(Flow, target_flow.id)

    assert Repo.get!(FlowNode, source_node.id).data["referenced_flow_id"] ==
             nil

    refute Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_id == ^source_node.id and
                   reference.target_flow_id == ^target_flow.id
             )
           )
  end

  test "pending Flow refs from preexisting trash remain recoverable after exact restore" do
    user = user_fixture()
    project = project_fixture(user)
    target_flow = flow_fixture(project, %{name: "Restored target"})
    caller_flow = flow_fixture(project, %{name: "Retained caller"})
    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    trash_source =
      node_fixture(caller_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target_flow.id}
      })

    assert {:ok, _deleted_node, _meta} = Flows.delete_node(trash_source)
    assert {:ok, _deleted_flow} = Flows.delete_flow(target_flow)

    assert %FlowNode{deleted_at: %DateTime{}, data: %{"referenced_flow_id" => nil}} =
             Repo.get!(FlowNode, trash_source.id)

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert %FlowNode{
             deleted_at: %DateTime{},
             data: %{"referenced_flow_id" => restored_target_id}
           } = Repo.get!(FlowNode, trash_source.id)

    assert restored_target_id == target_flow.id

    refute Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_id == ^trash_source.id and
                   reference.target_flow_id == ^target_flow.id
             )
           )

    assert {:ok, %FlowNode{id: restored_source_id, deleted_at: nil}} =
             Flows.restore_node(caller_flow.id, trash_source.id)

    assert restored_source_id == trash_source.id
  end

  test "pending cross-project Flow refs roll back target reactivation and leave the foreign source untouched" do
    user = user_fixture()
    project = project_fixture(user)
    target_flow = flow_fixture(project, %{name: "Target with corrupt pending ref"})
    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    assert {:ok, _deleted_flow} = Flows.delete_flow(target_flow)

    external_project = project_fixture(user)
    external_flow = flow_fixture(external_project, %{name: "Foreign source"})
    external_node = node_fixture(external_flow, %{type: "subflow", data: %{}})

    pending_ref =
      %EntityTrashRef{}
      |> EntityTrashRef.create_changeset(%{
        source_type: "flow_node",
        source_id: external_node.id,
        source_field: "data.referenced_flow_id",
        target_flow_id: target_flow.id
      })
      |> Repo.insert!()

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    external_before = external_callers_state(external_node.id, external_node.id)

    assert {:error,
            {:project_snapshot_flow_trash_reference_reconciliation_failed,
             {:project_restore_flow_trash_reference_cross_project_source, source_id, owner_project_id}}} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert source_id == external_node.id
    assert owner_project_id == external_project.id
    assert %Flow{deleted_at: %DateTime{}} = Repo.get!(Flow, target_flow.id)
    assert ProjectSnapshotBuilder.build_snapshot(project.id) == safety_snapshot
    assert external_callers_state(external_node.id, external_node.id) == external_before
    assert Repo.get!(EntityTrashRef, pending_ref.id)
  end

  test "restore fails before mutation when another project calls a current-only Flow" do
    user = user_fixture()
    project = project_fixture(user)
    retained_flow = flow_fixture(project, %{name: "Snapshot flow"})
    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    current_only_flow = flow_fixture(project, %{name: "Current-only flow"})

    external_project = project_fixture(user)
    external_flow = flow_fixture(external_project, %{name: "External caller"})
    active_caller = node_fixture(external_flow, %{type: "subflow", data: %{}})
    trash_caller = node_fixture(external_flow, %{type: "subflow", data: %{}})

    assert {:ok, %FlowNode{deleted_at: %DateTime{}}, _meta} =
             Flows.delete_node(trash_caller)

    referenced_data = %{"referenced_flow_id" => current_only_flow.id}

    assert {2, _rows} =
             Repo.update_all(
               from(node in FlowNode,
                 where: node.id in ^[active_caller.id, trash_caller.id]
               ),
               set: [data: referenced_data]
             )

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    external_before = external_callers_state(active_caller.id, trash_caller.id)

    assert {:error,
            {:project_snapshot_cross_project_flow_reference_conflict,
             [
               %{
                 node_id: active_caller_id,
                 referenced_flow_id: current_only_flow_id,
                 source_flow_id: external_flow_id,
                 source_in_trash: false,
                 source_project_id: external_project_id
               },
               %{
                 node_id: trash_caller_id,
                 referenced_flow_id: current_only_flow_id,
                 source_flow_id: external_flow_id,
                 source_in_trash: true,
                 source_project_id: external_project_id
               }
             ]}} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert active_caller_id == active_caller.id
    assert trash_caller_id == trash_caller.id
    assert current_only_flow_id == current_only_flow.id
    assert external_flow_id == external_flow.id
    assert external_project_id == external_project.id

    assert ProjectSnapshotBuilder.build_snapshot(project.id) == safety_snapshot
    assert external_callers_state(active_caller.id, trash_caller.id) == external_before
    assert %Flow{deleted_at: nil} = Repo.get!(Flow, retained_flow.id)
    assert %Flow{deleted_at: nil} = Repo.get!(Flow, current_only_flow.id)

    refute Repo.exists?(
             from(reference in EntityTrashRef,
               where: reference.target_flow_id == ^current_only_flow.id
             )
           )
  end

  test "project-scoped sweep cannot mutate an external reference introduced after preflight" do
    user = user_fixture()
    project = project_fixture(user)
    target_flow = flow_fixture(project, %{name: "Current-only target"})
    internal_flow = flow_fixture(project, %{name: "Internal caller"})

    internal_caller =
      node_fixture(internal_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target_flow.id}
      })

    external_project = project_fixture(user)
    external_flow = flow_fixture(external_project, %{name: "External caller"})
    external_caller = node_fixture(external_flow, %{type: "subflow", data: %{}})

    target_flow_id_string = Integer.to_string(target_flow.id)

    # This is the state observed by the restore preflight.
    refute Repo.exists?(
             from(node in FlowNode,
               join: source_flow in Flow,
               on: source_flow.id == node.flow_id,
               where: source_flow.project_id != ^project.id,
               where:
                 fragment("?->>'referenced_flow_id'", node.data) ==
                   ^target_flow_id_string
             )
           )

    # Corrupt external data appears in the window after preflight.
    assert {1, _rows} =
             Repo.update_all(
               from(node in FlowNode, where: node.id == ^external_caller.id),
               set: [data: %{"referenced_flow_id" => target_flow.id}]
             )

    assert {:ok, 1} =
             Flows.sweep_project_flow_references(project.id, target_flow.id)

    assert Repo.get!(FlowNode, internal_caller.id).data["referenced_flow_id"] ==
             nil

    assert Repo.get!(FlowNode, external_caller.id).data[
             "referenced_flow_id"
           ] == target_flow.id

    assert Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^internal_caller.id and
                   reference.source_field == "data.referenced_flow_id" and
                   reference.target_flow_id == ^target_flow.id
             )
           )

    refute Repo.exists?(
             from(reference in EntityTrashRef,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^external_caller.id and
                   reference.source_field == "data.referenced_flow_id" and
                   reference.target_flow_id == ^target_flow.id
             )
           )
  end

  defp external_callers_state(active_caller_id, trash_caller_id) do
    Repo.all(
      from(node in FlowNode,
        where: node.id in ^[active_caller_id, trash_caller_id],
        order_by: [asc: node.id],
        select: {node.id, node.flow_id, node.data, node.deleted_at}
      )
    )
  end

  defp reference_state(schema, sources) do
    sources
    |> Enum.flat_map(fn {source_type, source_id} ->
      Repo.all(
        from(reference in schema,
          where:
            reference.source_type == ^source_type and
              reference.source_id == ^source_id,
          order_by: [asc: reference.id]
        )
      )
    end)
    |> Enum.map(
      &Map.take(&1, [
        :id,
        :source_type,
        :source_id,
        :target_type,
        :target_id,
        :context,
        :flow_node_id,
        :block_id,
        :kind,
        :source_sheet,
        :source_variable,
        :inserted_at,
        :updated_at
      ])
    )
  end

  defp variable_assignment(sheet_shortcut, variable_name) do
    %{
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value_type" => "literal",
      "value" => 1
    }
  end

  defp variable_condition(sheet_shortcut, variable_name) do
    %{
      "logic" => "and",
      "blocks" => [
        %{
          "type" => "block",
          "rules" => [
            %{
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => 0
            }
          ]
        }
      ]
    }
  end
end
