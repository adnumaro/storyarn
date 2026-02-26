defmodule Storyarn.Flows.NodeUpdateTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  defp create_project_and_flow(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{user: user, project: project, flow: flow}
  end

  # ===========================================================================
  # batch_update_positions/2
  # ===========================================================================

  describe "batch_update_positions/2" do
    test "updates positions for multiple nodes" do
      %{flow: flow} = create_project_and_flow()
      node1 = node_fixture(flow, %{type: "dialogue", position_x: 0.0, position_y: 0.0})
      node2 = node_fixture(flow, %{type: "condition", position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: node1.id, position_x: 100.0, position_y: 200.0},
        %{id: node2.id, position_x: 300.0, position_y: 400.0}
      ]

      {:ok, count} = Flows.batch_update_positions(flow.id, positions)
      assert count == 2

      updated1 = Flows.get_node!(flow.id, node1.id)
      assert updated1.position_x == 100.0
      assert updated1.position_y == 200.0

      updated2 = Flows.get_node!(flow.id, node2.id)
      assert updated2.position_x == 300.0
      assert updated2.position_y == 400.0
    end

    test "returns {:ok, 0} for empty positions list" do
      %{flow: flow} = create_project_and_flow()

      {:ok, count} = Flows.batch_update_positions(flow.id, [])
      assert count == 0
    end
  end

  # ===========================================================================
  # update_node_data/2 — hub validation errors
  # ===========================================================================

  describe "update_node_data/2 — hub validation" do
    test "returns :hub_id_required when hub_id is nil" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "valid_hub", "label" => "Hub"}
        })

      result = Flows.update_node_data(hub, %{"hub_id" => nil, "label" => "Updated"})
      assert result == {:error, :hub_id_required}
    end

    test "returns :hub_id_required when hub_id is empty string" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "valid_hub", "label" => "Hub"}
        })

      result = Flows.update_node_data(hub, %{"hub_id" => "", "label" => "Updated"})
      assert result == {:error, :hub_id_required}
    end

    test "returns :hub_id_not_unique when hub_id collides with another hub" do
      %{flow: flow} = create_project_and_flow()

      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "existing_hub", "label" => "Hub 1"}
        })

      {:ok, hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "another_hub", "label" => "Hub 2"}
        })

      result = Flows.update_node_data(hub2, %{"hub_id" => "existing_hub", "label" => "Hub 2"})
      assert result == {:error, :hub_id_not_unique}
    end
  end

  # ===========================================================================
  # update_node_data/2 — hub_id rename cascade
  # ===========================================================================

  describe "update_node_data/2 — hub_id rename cascades to jumps" do
    test "renaming hub_id updates referencing jump nodes" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "old_hub", "label" => "Hub"}
        })

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "old_hub"}
        })

      {:ok, _updated_hub, meta} =
        Flows.update_node_data(hub, %{"hub_id" => "new_hub", "label" => "Hub"})

      assert meta.renamed_jumps == 1

      # Verify the jump's target_hub_id was updated
      updated_jump = Flows.get_node!(flow.id, jump.id)
      assert updated_jump.data["target_hub_id"] == "new_hub"
    end

    test "updating hub data without changing hub_id reports zero renamed jumps" do
      %{flow: flow} = create_project_and_flow()

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          data: %{"hub_id" => "same_hub", "label" => "Hub"}
        })

      {:ok, _updated, meta} =
        Flows.update_node_data(hub, %{"hub_id" => "same_hub", "label" => "Updated Label"})

      assert meta.renamed_jumps == 0
    end
  end

  # ===========================================================================
  # update_node_data/2 — non-hub returns zero renamed_jumps
  # ===========================================================================

  describe "update_node_data/2 — non-hub nodes" do
    test "updating non-hub node data returns renamed_jumps: 0" do
      %{flow: flow} = create_project_and_flow()

      {:ok, dialogue} =
        Flows.create_node(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello"}
        })

      {:ok, _updated, meta} =
        Flows.update_node_data(dialogue, %{"text" => "Updated text"})

      assert meta.renamed_jumps == 0
    end
  end

  # ===========================================================================
  # change_node/2
  # ===========================================================================

  describe "change_node/2" do
    test "returns a changeset for a node" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset = Flows.change_node(node)
      assert %Ecto.Changeset{} = changeset
    end

    test "returns a changeset with attrs applied" do
      %{flow: flow} = create_project_and_flow()
      node = node_fixture(flow, %{type: "dialogue"})

      changeset = Flows.change_node(node, %{position_x: 999.0})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :position_x) == 999.0
    end
  end
end
