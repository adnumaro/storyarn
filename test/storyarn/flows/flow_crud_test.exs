defmodule Storyarn.Flows.FlowCrudTest do
  use Storyarn.DataCase

  alias Storyarn.Flows

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  describe "create_linked_flow/4" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      parent_flow = flow_fixture(project, %{name: "Parent Flow"})
      %{project: project, parent_flow: parent_flow}
    end

    test "creates child flow with parent_id set", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow, node: updated_node}} =
        Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.parent_id == parent_flow.id
      assert updated_node.data["referenced_flow_id"] == new_flow.id
    end

    test "uses node label as flow name when present", %{
      project: project,
      parent_flow: parent_flow
    } do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "Victory Ending",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.name == "Victory Ending"
    end

    test "uses fallback name when no label", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.name == "Parent Flow - Sub"
    end

    test "new flow has entry + exit nodes from create_flow/2", %{
      project: project,
      parent_flow: parent_flow
    } do
      node =
        node_fixture(parent_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => nil}
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      full_flow = Flows.get_flow!(project.id, new_flow.id)
      types = Enum.map(full_flow.nodes, & &1.type) |> Enum.sort()
      assert types == ["entry", "exit"]
    end

    test "accepts custom name via opts", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{"label" => "Ignored", "referenced_flow_id" => nil}
        })

      {:ok, %{flow: new_flow}} =
        Flows.create_linked_flow(project, parent_flow, node, name: "Custom Name")

      assert new_flow.name == "Custom Name"
    end
  end
end
