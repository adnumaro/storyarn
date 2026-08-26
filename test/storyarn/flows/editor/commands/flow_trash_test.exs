defmodule Storyarn.Flows.FlowTrashTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  describe "Flow deletion and restoration" do
    test "sweeps referenced_flow_id on Flow nodes and restores it" do
      user = user_fixture()
      project = project_fixture(user)
      host_flow = flow_fixture(project)
      target_flow = flow_fixture(project)

      subflow_node =
        node_fixture(host_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => target_flow.id}
        })

      exit_node =
        node_fixture(host_flow, %{
          type: "exit",
          data: %{
            "referenced_flow_id" => target_flow.id,
            "exit_mode" => "flow_reference"
          }
        })

      assert {:ok, deleted} = Flows.delete_flow(target_flow)
      assert %DateTime{} = deleted.deleted_at
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == nil
      assert Repo.get!(FlowNode, exit_node.id).data["referenced_flow_id"] == nil

      refs = Repo.all(EntityTrashRef)
      assert length(refs) == 2

      assert Enum.all?(refs, fn ref ->
               ref.source_type == "flow_node" and
                 ref.source_field == "data.referenced_flow_id" and
                 ref.target_flow_id == target_flow.id
             end)

      assert {:ok, restored} = Flows.restore_flow(deleted)
      assert is_nil(restored.deleted_at)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == target_flow.id
      assert Repo.get!(FlowNode, exit_node.id).data["referenced_flow_id"] == target_flow.id
      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end

    test "restoration does not overwrite a reference repointed while the target was in trash" do
      project = project_fixture(user_fixture())
      host_flow = flow_fixture(project)
      target_a = flow_fixture(project)
      target_b = flow_fixture(project)

      subflow_node =
        node_fixture(host_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => target_a.id}
        })

      assert {:ok, deleted_a} = Flows.delete_flow(target_a)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == nil

      node = Repo.get!(FlowNode, subflow_node.id)
      new_data = Map.put(node.data, "referenced_flow_id", target_b.id)
      node |> Ecto.Changeset.change(%{data: new_data}) |> Repo.update!()

      assert {:ok, _restored} = Flows.restore_flow(deleted_a)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == target_b.id
      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end

    test "cascade deletion sweeps references to descendant Flows too" do
      project = project_fixture(user_fixture())
      host_flow = flow_fixture(project)
      parent = flow_fixture(project)
      child = flow_fixture(project, %{parent_id: parent.id})

      node =
        node_fixture(host_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => child.id}
        })

      assert {:ok, _deleted_parent} = Flows.delete_flow(parent)
      assert Repo.get!(FlowNode, node.id).data["referenced_flow_id"] == nil

      assert Repo.exists?(
               from(ref in EntityTrashRef,
                 where: ref.source_id == ^node.id and ref.target_flow_id == ^child.id
               )
             )
    end
  end
end
