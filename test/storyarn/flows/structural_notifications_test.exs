defmodule Storyarn.Flows.StructuralNotificationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Flows
  alias Storyarn.Notifications.Notification
  alias Storyarn.Repo

  setup do
    actor = user_fixture()
    direct_member = user_fixture()
    inherited_member = user_fixture()
    workspace = workspace_fixture(actor)
    project = project_fixture(actor, %{workspace: workspace})

    membership_fixture(project, direct_member, "viewer")
    workspace_membership_fixture(workspace, inherited_member, "viewer")

    %{
      actor: actor,
      actor_scope: user_scope_fixture(actor),
      direct_member: direct_member,
      inherited_member: inherited_member,
      project: project
    }
  end

  test "scoped create notifies direct and inherited members but excludes the actor", context do
    assert {:ok, flow} =
             Flows.create_flow(context.actor_scope, context.project, %{name: "Opening"})

    notifications = flow_notifications(context.project)

    assert notifications |> Enum.map(& &1.recipient_id) |> Enum.sort() ==
             Enum.sort([context.direct_member.id, context.inherited_member.id])

    assert Enum.all?(notifications, &(&1.actor_id == context.actor.id))
    assert Enum.all?(notifications, &(&1.kind == "content_created"))
    assert Enum.all?(notifications, &(&1.entity_id == flow.id))
    assert Enum.all?(notifications, &(&1.entity_name == "Opening"))
    refute Enum.any?(notifications, &(&1.recipient_id == context.actor.id))
  end

  test "scoped cascade delete emits only the root with its locked current name", context do
    root = flow_fixture(context.project, %{name: "Stale Root"})
    child = flow_fixture(context.project, %{name: "Child", parent_id: root.id})
    assert {:ok, _renamed} = Flows.update_flow(root, %{name: "Locked Root"})
    assert flow_notifications(context.project) == []

    assert {:ok, %{entity: deleted, deleted_ids: deleted_ids}} =
             Flows.delete_flow_subtree(context.actor_scope, root)

    assert deleted.id == root.id
    assert Enum.sort(deleted_ids) == Enum.sort([root.id, child.id])

    notifications = flow_notifications(context.project)

    assert length(notifications) == 2
    assert Enum.all?(notifications, &(&1.kind == "content_deleted"))
    assert Enum.all?(notifications, &(&1.entity_id == root.id))
    assert Enum.all?(notifications, &(&1.entity_name == "Locked Root"))
    refute Enum.any?(notifications, &(&1.entity_id == child.id))
  end

  test "updates and legacy unscoped create and delete APIs stay silent", context do
    assert {:ok, flow} = Flows.create_flow(context.project, %{name: "Quiet Flow"})
    assert {:ok, updated} = Flows.update_flow(flow, %{name: "Still Quiet"})
    assert {:ok, _deleted} = Flows.delete_flow(updated)

    assert flow_notifications(context.project) == []
  end

  test "scoped linked-flow creation notifies for the committed child", context do
    parent = flow_fixture(context.project, %{name: "Parent"})

    node =
      node_fixture(parent, %{
        type: "exit",
        data: %{
          "label" => "Victory Ending",
          "exit_mode" => "flow_reference",
          "referenced_flow_id" => nil
        }
      })

    assert {:ok, %{flow: child, node: updated_node}} =
             Flows.create_linked_flow(context.actor_scope, context.project, parent, node, [])

    assert updated_node.data["referenced_flow_id"] == child.id

    notifications = flow_notifications(context.project)

    assert length(notifications) == 2
    assert Enum.all?(notifications, &(&1.kind == "content_created"))
    assert Enum.all?(notifications, &(&1.entity_id == child.id))
    assert Enum.all?(notifications, &(&1.entity_name == "Victory Ending"))
  end

  test "a failed scoped linked-flow transaction leaves no flow or notification", context do
    parent = flow_fixture(context.project, %{name: "Parent"})

    node =
      parent
      |> node_fixture(%{type: "hub", data: %{"hub_id" => "rollback"}})
      |> Ecto.Changeset.change(data: %{})
      |> Repo.update!()

    assert {:error, :node, reason, %{flow: rolled_back_flow}} =
             Flows.create_linked_flow(context.actor_scope, context.project, parent, node, [])

    assert match?({:invalid_referenced_flow, "hub", _flow_id}, reason)
    assert is_nil(Flows.get_flow(context.project.id, rolled_back_flow.id))
    assert flow_notifications(context.project) == []
  end

  defp flow_notifications(project) do
    Repo.all(
      from(notification in Notification,
        where:
          notification.project_id == ^project.id and
            notification.entity_type == "flow",
        order_by: [asc: notification.id]
      )
    )
  end
end
