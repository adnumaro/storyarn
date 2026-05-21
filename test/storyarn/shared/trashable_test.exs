defmodule Storyarn.Shared.TrashableTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Shared.Trashable

  # ===========================================================================
  # target_type!/1
  # ===========================================================================

  describe "target_type!/1" do
    test "returns :flow for Flow" do
      assert Trashable.target_type!(%Flow{}) == :flow
      assert Trashable.target_type!(Flow) == :flow
    end

    test "raises for unregistered schema" do
      assert_raise ArgumentError, ~r/is not registered in Trashable/, fn ->
        Trashable.target_type!(Storyarn.Accounts.User)
      end
    end
  end

  # ===========================================================================
  # soft_delete/1 + restore/1 on Flow (JSONB-based inbound ref)
  # ===========================================================================

  describe "soft_delete/1 + restore/1 on Flow" do
    test "sweeps referenced_flow_id on subflow nodes, restore re-applies" do
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
          data: %{"referenced_flow_id" => target_flow.id, "exit_mode" => "flow_reference"}
        })

      # Delete via Trashable
      assert {:ok, deleted} = Trashable.soft_delete(target_flow)
      assert %DateTime{} = deleted.deleted_at

      # Refs nulled
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == nil
      assert Repo.get!(FlowNode, exit_node.id).data["referenced_flow_id"] == nil

      # Trash rows recorded
      refs = Repo.all(EntityTrashRef)
      assert length(refs) == 2

      assert Enum.all?(refs, fn r ->
               r.source_type == "flow_node" and
                 r.source_field == "data.referenced_flow_id" and
                 r.target_flow_id == target_flow.id
             end)

      # Restore
      assert {:ok, restored} = Trashable.restore(deleted)
      assert is_nil(restored.deleted_at)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == target_flow.id
      assert Repo.get!(FlowNode, exit_node.id).data["referenced_flow_id"] == target_flow.id
      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end

    test "restore is conservative: does not yank a ref the user repointed" do
      user = user_fixture()
      project = project_fixture(user)
      host_flow = flow_fixture(project)
      target_a = flow_fixture(project)
      target_b = flow_fixture(project)

      subflow_node =
        node_fixture(host_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => target_a.id}
        })

      {:ok, deleted_a} = Trashable.soft_delete(target_a)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == nil

      # User re-points the subflow to target_b while A is in trash
      node = Repo.get!(FlowNode, subflow_node.id)
      new_data = Map.put(node.data, "referenced_flow_id", target_b.id)
      node |> Ecto.Changeset.change(%{data: new_data}) |> Repo.update!()

      # Restore A — should NOT yank subflow from target_b
      {:ok, _} = Trashable.restore(deleted_a)
      assert Repo.get!(FlowNode, subflow_node.id).data["referenced_flow_id"] == target_b.id
      assert Repo.aggregate(EntityTrashRef, :count) == 0
    end
  end
end
