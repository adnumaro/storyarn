defmodule Storyarn.Projects.FlowProjectTrashTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Projects.FlowProjectTrash
  alias Storyarn.Projects.Persistence.EntityReferenceRecord, as: EntityReference
  alias Storyarn.Projects.Persistence.FlowEntityTrashReferenceRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.LocalizedTextRecord
  alias Storyarn.Projects.Persistence.VariableReferenceRecord
  alias Storyarn.Repo

  test "exact replacement suspends root and descendant references and reports affected Flows" do
    project = project_fixture(user_fixture())
    host = flow_fixture(project)
    parent = flow_fixture(project)
    child = flow_fixture(project, %{parent_id: parent.id})

    parent_reference =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => parent.id}
      })

    child_reference =
      node_fixture(host, %{
        type: "exit",
        data: %{
          "exit_mode" => "flow_reference",
          "referenced_flow_id" => child.id
        }
      })

    assert {:ok, result} =
             Repo.transaction(fn ->
               FlowProjectTrash.delete_subtree_in_transaction(%FlowRecord{
                 id: parent.id,
                 project_id: project.id
               })
             end)

    assert result.affected_flow_ids == [host.id]
    assert Enum.sort(result.deleted_ids) == Enum.sort([parent.id, child.id])
    assert %DateTime{} = Repo.get!(FlowRecord, parent.id).deleted_at
    assert %DateTime{} = Repo.get!(FlowRecord, child.id).deleted_at

    assert Repo.get!(FlowNodeRecord, parent_reference.id).data["referenced_flow_id"] == nil
    assert Repo.get!(FlowNodeRecord, child_reference.id).data["referenced_flow_id"] == nil

    refs = Repo.all(FlowEntityTrashReferenceRecord)

    assert Enum.any?(refs, fn ref ->
             ref.source_id == parent_reference.id and
               ref.source_field == "data.referenced_flow_id" and
               ref.target_flow_id == parent.id
           end)

    assert Enum.any?(refs, fn ref ->
             ref.source_id == child_reference.id and
               ref.source_field == "data.referenced_flow_id" and
               ref.target_flow_id == child.id
           end)
  end

  test "root sweeps stay project-scoped while descendant sweeps preserve historical global behavior" do
    owner = user_fixture()
    project = project_fixture(owner)
    external_project = project_fixture(owner)
    parent = flow_fixture(project)
    child = flow_fixture(project, %{parent_id: parent.id})
    external_host = flow_fixture(external_project)

    parent_reference =
      Repo.insert!(%FlowNodeRecord{
        flow_id: external_host.id,
        type: "subflow",
        data: %{"referenced_flow_id" => parent.id}
      })

    child_reference =
      Repo.insert!(%FlowNodeRecord{
        flow_id: external_host.id,
        type: "exit",
        data: %{
          "exit_mode" => "flow_reference",
          "referenced_flow_id" => child.id
        }
      })

    assert {:ok, %{affected_flow_ids: []}} =
             Repo.transaction(fn ->
               FlowProjectTrash.delete_subtree_in_transaction(%FlowRecord{
                 id: parent.id,
                 project_id: project.id
               })
             end)

    assert Repo.get!(FlowNodeRecord, parent_reference.id).data["referenced_flow_id"] == parent.id
    assert Repo.get!(FlowNodeRecord, child_reference.id).data["referenced_flow_id"] == nil

    refute Repo.exists?(
             from(ref in FlowEntityTrashReferenceRecord,
               where: ref.source_id == ^parent_reference.id and ref.target_flow_id == ^parent.id
             )
           )

    assert Repo.exists?(
             from(ref in FlowEntityTrashReferenceRecord,
               where: ref.source_id == ^child_reference.id and ref.target_flow_id == ^child.id
             )
           )
  end

  test "Project restores a Flow, suspended source refs and owned reference projections" do
    project = project_fixture(user_fixture())
    _language = language_fixture(project)
    host = flow_fixture(project, %{name: "Host"})
    target = flow_fixture(project, %{name: "Target"})
    speaker = sheet_fixture(project, %{name: "Speaker"})
    stats = sheet_fixture(project, %{name: "Stats", shortcut: "game.stats"})

    variable =
      block_fixture(stats, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    source =
      node_fixture(host, %{
        type: "subflow",
        data: %{"referenced_flow_id" => target.id}
      })

    dialogue =
      node_fixture(target, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => speaker.id,
          "text" => "Hello",
          "responses" => []
        }
      })

    instruction =
      node_fixture(target, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => "set-health",
              "sheet" => stats.shortcut,
              "variable" => variable.variable_name,
              "operator" => "set",
              "value" => "100",
              "value_type" => "literal"
            }
          ]
        }
      })

    assert {:ok, dialogue, _meta} = Flows.update_node_data(dialogue, dialogue.data)
    assert {:ok, instruction, _meta} = Flows.update_node_data(instruction, instruction.data)

    assert %LocalizedTextRecord{source_text: "Hello", archived_at: nil} =
             Repo.one!(
               from(text in LocalizedTextRecord,
                 where:
                   text.source_type == "flow_node" and text.source_id == ^dialogue.id and
                     text.source_field == "text" and text.locale_code == "es"
               )
             )

    assert {:ok, _deleted} = Flows.delete_flow(target)

    assert %DateTime{} =
             Repo.one!(
               from(text in LocalizedTextRecord,
                 where:
                   text.source_type == "flow_node" and text.source_id == ^dialogue.id and
                     text.source_field == "text" and text.locale_code == "es",
                 select: text.archived_at
               )
             )

    Repo.delete_all(
      from(reference in EntityReference,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^dialogue.id
      )
    )

    Repo.delete_all(
      from(reference in VariableReferenceRecord,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^instruction.id
      )
    )

    assert {:ok, restored} = Projects.restore_trashed_flow(project.id, target.id)
    assert restored.id == target.id
    assert Repo.get!(FlowRecord, target.id).deleted_at == nil
    assert Repo.get!(FlowNodeRecord, source.id).data["referenced_flow_id"] == target.id

    assert %LocalizedTextRecord{source_text: "Hello", archived_at: nil} =
             Repo.one!(
               from(text in LocalizedTextRecord,
                 where:
                   text.source_type == "flow_node" and text.source_id == ^dialogue.id and
                     text.source_field == "text" and text.locale_code == "es"
               )
             )

    assert Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^dialogue.id and
                   reference.target_type == "sheet" and
                   reference.target_id == ^speaker.id
             )
           )

    assert Repo.exists?(
             from(reference in VariableReferenceRecord,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^instruction.id and
                   reference.block_id == ^variable.id
             )
           )

    refute Repo.exists?(
             from(ref in FlowEntityTrashReferenceRecord,
               where: ref.target_flow_id == ^target.id
             )
           )
  end

  test "Project restore rolls back and emits no dashboard invalidation when localization fails" do
    project = project_fixture(user_fixture())
    flow = flow_fixture(project, %{name: "Localization rollback"})
    _dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Runtime line"}})

    assert {:ok, _deleted} = Flows.delete_flow(flow)
    :ok = Collaboration.subscribe_dashboard(project.id)

    assert {:error, :forced_localization_failure} =
             FlowProjectTrash.restore(project.id, flow.id, fn restored_flow_id ->
               assert restored_flow_id == flow.id
               {:error, :forced_localization_failure}
             end)

    assert %DateTime{} = Repo.get!(FlowRecord, flow.id).deleted_at
    refute_receive {:dashboard_invalidate, :flows}, 20
  end

  test "Project restore cannot cross its supplied project boundary" do
    owner = user_fixture()
    project = project_fixture(owner)
    other_project = project_fixture(owner)
    flow = flow_fixture(project)

    assert {:ok, _deleted} = Flows.delete_flow(flow)

    assert {:error, :flow_not_deleted} =
             Projects.restore_trashed_flow(other_project.id, flow.id)

    assert %DateTime{} = Repo.get!(FlowRecord, flow.id).deleted_at
  end
end
