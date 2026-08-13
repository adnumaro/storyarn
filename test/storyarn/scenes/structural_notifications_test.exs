defmodule Storyarn.Scenes.StructuralNotificationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Notifications
  alias Storyarn.Scenes

  setup do
    actor = user_fixture()
    recipient = user_fixture()
    project = project_fixture(actor)
    membership_fixture(project, recipient)

    %{
      actor: actor,
      actor_scope: user_scope_fixture(actor),
      recipient: recipient,
      recipient_scope: user_scope_fixture(recipient),
      project: project
    }
  end

  test "scoped creation notifies another member with the persisted scene identity", %{
    actor: actor,
    actor_scope: actor_scope,
    recipient: recipient,
    recipient_scope: recipient_scope,
    project: project
  } do
    :ok = Notifications.subscribe(recipient_scope)
    :ok = Notifications.subscribe(actor_scope)

    assert {:ok, scene} =
             Scenes.create_scene(actor_scope, project, %{
               name: "Northern Reach",
               description: "A persisted scene"
             })

    assert [notification] = Notifications.list_notifications(recipient_scope)
    assert notification.recipient_id == recipient.id
    assert notification.actor_id == actor.id
    assert notification.project_id == project.id
    assert notification.kind == "content_created"
    assert notification.entity_type == "scene"
    assert notification.entity_id == scene.id
    assert notification.entity_name == scene.name
    assert notification.entity_name == "Northern Reach"

    assert Notifications.list_notifications(actor_scope) == []
    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50
  end

  test "scoped subtree deletion reports only the root and uses its locked current name", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    stale_parent = scene_fixture(project, %{name: "Old Region Name"})

    child =
      scene_fixture(project, %{
        name: "Child Location",
        parent_id: stale_parent.id
      })

    assert {:ok, updated_parent} =
             Scenes.update_scene(stale_parent, %{name: "Current Region Name"})

    assert updated_parent.name == "Current Region Name"
    assert Notifications.list_notifications(recipient_scope) == []
    :ok = Notifications.subscribe(recipient_scope)
    :ok = Notifications.subscribe(actor_scope)

    assert {:ok, %{entity: deleted, deleted_ids: deleted_ids}} =
             Scenes.delete_scene_subtree(actor_scope, stale_parent)

    assert deleted.id == stale_parent.id
    assert Enum.sort(deleted_ids) == Enum.sort([stale_parent.id, child.id])

    assert [notification] = Notifications.list_notifications(recipient_scope)
    assert notification.kind == "content_deleted"
    assert notification.entity_type == "scene"
    assert notification.entity_id == stale_parent.id
    assert notification.entity_name == "Current Region Name"
    refute notification.entity_id == child.id
    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50
  end

  test "updates and the unscoped create/delete API stay silent", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    assert {:ok, scene} = Scenes.create_scene(project, %{name: "Silent Scene"})
    assert {:ok, updated} = Scenes.update_scene(scene, %{name: "Still Silent"})
    assert {:ok, deleted} = Scenes.delete_scene(updated)
    assert deleted.deleted_at

    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
  end

  test "a rejected scoped creation rolls back the scene and its notifications", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    outsider_scope = user_scope_fixture(user_fixture())
    :ok = Notifications.subscribe(recipient_scope)
    :ok = Notifications.subscribe(actor_scope)
    :ok = Notifications.subscribe(outsider_scope)

    assert {:error, :not_found} =
             Scenes.create_scene(outsider_scope, project, %{name: "Must Roll Back"})

    refute Enum.any?(Scenes.list_scenes(project.id), &(&1.name == "Must Roll Back"))
    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
    assert Notifications.list_notifications(outsider_scope) == []
    refute_receive :notifications_changed, 50
  end
end
