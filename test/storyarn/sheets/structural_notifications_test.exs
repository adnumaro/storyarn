defmodule Storyarn.Sheets.StructuralNotificationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Repo
  alias Storyarn.Sheets

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
      project: project,
      workspace: workspace
    }
  end

  test "scoped create notifies direct and inherited members but excludes the actor", context do
    :ok = Notifications.subscribe(user_scope_fixture(context.direct_member))
    :ok = Notifications.subscribe(context.actor_scope)

    assert {:ok, sheet} =
             Sheets.create_sheet(context.actor_scope, context.project, %{name: "Main Characters"})

    notifications = sheet_notifications(context.project)

    assert notifications |> Enum.map(& &1.recipient_id) |> Enum.sort() ==
             Enum.sort([context.direct_member.id, context.inherited_member.id])

    assert Enum.all?(notifications, &(&1.actor_id == context.actor.id))
    assert Enum.all?(notifications, &(&1.kind == "content_created"))
    assert Enum.all?(notifications, &(&1.entity_id == sheet.id))
    assert Enum.all?(notifications, &(&1.entity_name == "Main Characters"))
    refute Enum.any?(notifications, &(&1.recipient_id == context.actor.id))
    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50
  end

  test "scoped cascade delete emits only the root with its locked current name", context do
    root = sheet_fixture(context.project, %{name: "Stale Root"})
    child = child_sheet_fixture(context.project, root, %{name: "Child"})
    assert {:ok, _renamed} = Sheets.update_sheet(root, %{name: "Locked Root"})
    assert sheet_notifications(context.project) == []
    :ok = Notifications.subscribe(user_scope_fixture(context.direct_member))
    :ok = Notifications.subscribe(context.actor_scope)

    assert {:ok, %{entity: deleted, deleted_ids: deleted_ids}} =
             Sheets.delete_sheet_subtree(context.actor_scope, root)

    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50

    assert deleted.id == root.id
    assert Enum.sort(deleted_ids) == Enum.sort([root.id, child.id])

    notifications = sheet_notifications(context.project)

    assert length(notifications) == 2
    assert Enum.all?(notifications, &(&1.kind == "content_deleted"))
    assert Enum.all?(notifications, &(&1.entity_id == root.id))
    assert Enum.all?(notifications, &(&1.entity_name == "Locked Root"))
    refute Enum.any?(notifications, &(&1.entity_id == child.id))
  end

  test "updates and legacy unscoped create and delete APIs stay silent", context do
    assert {:ok, sheet} = Sheets.create_sheet(context.project, %{name: "Quiet Sheet"})
    assert {:ok, updated} = Sheets.update_sheet(sheet, %{name: "Still Quiet"})
    assert {:ok, _deleted} = Sheets.delete_sheet(updated)

    assert sheet_notifications(context.project) == []
  end

  test "a later inherited member is not notified when a deleted sheet lifecycle repeats", context do
    sheet = sheet_fixture(context.project, %{name: "One-time deletion"})

    assert {:ok, %{entity: deleted}} =
             Sheets.delete_sheet_subtree(context.actor_scope, sheet)

    late_member = user_fixture()
    workspace_membership_fixture(context.workspace, late_member, "viewer")
    late_member_scope = user_scope_fixture(late_member)
    :ok = Notifications.subscribe(late_member_scope)

    assert {:ok, restored} = Sheets.restore_sheet(deleted)

    assert {:ok, %{entity: redeleted}} =
             Sheets.delete_sheet_subtree(context.actor_scope, restored)

    assert redeleted.id == sheet.id

    assert Repo.all(
             from(notification in Notification,
               where:
                 notification.project_id == ^context.project.id and
                   notification.recipient_id == ^late_member.id and
                   notification.entity_type == "sheet" and
                   notification.entity_id == ^sheet.id
             )
           ) == []

    refute_receive :notifications_changed
  end

  defp sheet_notifications(project) do
    Repo.all(
      from(notification in Notification,
        where:
          notification.project_id == ^project.id and
            notification.entity_type == "sheet",
        order_by: [asc: notification.id]
      )
    )
  end
end
