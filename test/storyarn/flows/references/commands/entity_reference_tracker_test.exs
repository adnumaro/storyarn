defmodule Storyarn.Flows.References.Commands.EntityReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Multi
  alias Storyarn.Flows
  alias Storyarn.Flows.EntityReferenceTracker
  alias Storyarn.Flows.References.Projections.EntityReferenceRecord
  alias Storyarn.Repo

  test "indexes valid mentions nested outside the top-level dialogue text" do
    %{project: project} = setup_project()
    target_sheet = sheet_fixture(project, %{name: "Nested mention"})
    flow = flow_fixture(project, %{name: "Nested rich text"})

    mention_html =
      ~s(<p><span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Nested</span></p>)

    node =
      raw_node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Top-level text",
          "responses" => [%{"id" => "response_nested", "text" => mention_html}]
        }
      })

    assert :ok = EntityReferenceTracker.update_references(node)

    assert %EntityReferenceRecord{source_type: "flow_node", context: "dialogue"} =
             Repo.get_by!(EntityReferenceRecord,
               source_id: node.id,
               target_type: "sheet",
               target_id: target_sheet.id
             )
  end

  test "infers the source project and rejects cross-project targets without opts" do
    %{user: user, project: project} = setup_project()
    other_project = project_fixture(user)
    foreign_target = sheet_fixture(other_project, %{name: "Foreign target"})
    flow = flow_fixture(project, %{name: "Implicit project scope"})

    node =
      raw_node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => foreign_target.id,
          "text" => "Do not cross projects"
        }
      })

    assert :ok = EntityReferenceTracker.update_references(node)

    refute Repo.get_by(EntityReferenceRecord,
             source_type: "flow_node",
             source_id: node.id,
             target_type: "sheet",
             target_id: foreign_target.id
           )
  end

  test "ignores inputs without a persisted node data map and rejects an invalid project scope" do
    %{project: project} = setup_project()
    flow = flow_fixture(project, %{name: "Invalid project scope"})
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

    assert :ok = EntityReferenceTracker.update_references(%{id: 999, data: nil})
    assert :ok = EntityReferenceTracker.update_references("not a map")

    assert {:error, {:invalid_project_id, :invalid}} =
             EntityReferenceTracker.update_references(node, project_id: :invalid)
  end

  test "preserves existing references when the requested project does not own the node" do
    %{project: project} = setup_project()
    other_project = project_fixture()
    target_sheet = sheet_fixture(project, %{name: "Existing target"})
    flow = flow_fixture(project, %{name: "Project scope rollback"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
      })

    assert EntityReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1

    assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
             EntityReferenceTracker.update_references(node,
               project_id: other_project.id
             )

    assert node_id == node.id
    assert project_id == other_project.id
    assert EntityReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1
  end

  test "rejects a deleted Flow node when rebuilding references directly" do
    %{project: project} = setup_project()
    target_sheet = sheet_fixture(project, %{name: "Deleted node target"})
    flow = flow_fixture(project, %{name: "Deleted node source"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => target_sheet.id, "text" => "Hello"}
      })

    assert EntityReferenceTracker.count_backlinks("sheet", target_sheet.id) == 1
    assert {:ok, _deleted_node, _meta} = Flows.delete_node(node)
    assert EntityReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0

    assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
             EntityReferenceTracker.update_references(node,
               project_id: project.id
             )

    assert node_id == node.id
    assert project_id == project.id
    assert EntityReferenceTracker.count_backlinks("sheet", target_sheet.id) == 0
  end

  test "rejects a node whose owning Flow is in trash when rebuilding directly" do
    %{project: project} = setup_project()
    original_target = sheet_fixture(project, %{name: "Deleted flow original target"})
    replacement_target = sheet_fixture(project, %{name: "Deleted flow replacement target"})
    flow = flow_fixture(project, %{name: "Deleted flow source"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => original_target.id, "text" => "Hello"}
      })

    assert EntityReferenceTracker.count_backlinks("sheet", original_target.id) == 1
    assert {:ok, _deleted_flow} = Flows.delete_flow(flow)
    assert EntityReferenceTracker.count_backlinks("sheet", original_target.id) == 1

    node =
      Repo.update!(
        Ecto.Changeset.change(node,
          data: %{
            "speaker_sheet_id" => replacement_target.id,
            "text" => "Changed while in trash"
          }
        )
      )

    assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
             EntityReferenceTracker.update_references(node,
               project_id: project.id
             )

    assert node_id == node.id
    assert project_id == project.id
    assert EntityReferenceTracker.count_backlinks("sheet", original_target.id) == 1
    assert EntityReferenceTracker.count_backlinks("sheet", replacement_target.id) == 0
  end

  test "returns an error from Ecto.Multi and rolls back preceding operations" do
    %{project: project} = setup_project()
    other_project = project_fixture()
    target_sheet = sheet_fixture(project, %{name: "Original name"})
    flow = flow_fixture(project, %{name: "Outer transaction rollback"})
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

    result =
      Multi.new()
      |> Multi.update(
        :rename_target,
        Ecto.Changeset.change(target_sheet, name: "Sentinel name")
      )
      |> Multi.run(:rebuild_references, fn _repo, _changes ->
        EntityReferenceTracker.update_references(node,
          project_id: other_project.id
        )
      end)
      |> Repo.transaction()

    assert {:error, :rebuild_references, {:flow_node_project_mismatch, node_id, project_id},
            %{rename_target: _renamed_sheet}} = result

    assert node_id == node.id
    assert project_id == other_project.id
    assert Repo.reload!(target_sheet).name == "Original name"
  end

  test "lets an outer transaction explicitly propagate a project ownership error" do
    %{project: project} = setup_project()
    other_project = project_fixture()
    target_sheet = sheet_fixture(project, %{name: "Original name"})
    flow = flow_fixture(project, %{name: "Explicit outer rollback"})
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

    result =
      Repo.transaction(fn ->
        Repo.update!(Ecto.Changeset.change(target_sheet, name: "Sentinel name"))

        case EntityReferenceTracker.update_references(node,
               project_id: other_project.id
             ) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    assert {:error, {:flow_node_project_mismatch, node_id, project_id}} = result
    assert node_id == node.id
    assert project_id == other_project.id
    assert Repo.reload!(target_sheet).name == "Original name"
  end

  defp setup_project do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end
end
