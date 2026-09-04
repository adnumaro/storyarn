defmodule Storyarn.Platform.CommentNotificationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Repo

  setup do
    actor = user_fixture()
    direct = user_fixture()
    inherited = user_fixture()
    stranger = user_fixture()
    workspace = workspace_fixture(actor)
    project = project_fixture(actor, %{workspace: workspace})
    membership_fixture(project, direct, "viewer")
    workspace_membership_fixture(workspace, inherited, "viewer")

    %{
      actor: actor,
      direct: direct,
      inherited: inherited,
      stranger: stranger,
      project: project,
      comment_id: System.unique_integer([:positive])
    }
  end

  test "delivers once to selected effective members, preferring mentions and excluding the actor", context do
    recipients = [
      %{user_id: context.direct.id, kind: "comment_reply"},
      %{user_id: context.direct.id, kind: "comment_mention"},
      %{user_id: context.direct.id, kind: "comment_reply"},
      %{user_id: context.inherited.id, kind: "comment_reply"},
      %{user_id: context.actor.id, kind: "comment_mention"},
      %{user_id: context.stranger.id, kind: "comment_mention"},
      %{user_id: 9_223_372_036_854_775_807, kind: "comment_mention"}
    ]

    :ok = Platform.subscribe_notifications(user_scope_fixture(context.direct))

    assert {:ok, {:created, notifications} = outcome} = deliver(context, recipients)
    assert length(notifications) == 2
    assert Enum.find(notifications, &(&1.recipient_id == context.direct.id)).kind == "comment_mention"
    assert Enum.find(notifications, &(&1.recipient_id == context.inherited.id)).kind == "comment_reply"
    assert Enum.all?(notifications, &(&1.actor_id == context.actor.id))
    assert Enum.all?(notifications, &(&1.entity_type == "comment" and &1.entity_id == context.comment_id))
    assert Enum.all?(notifications, &(is_nil(&1.entity_name) and is_nil(&1.status)))
    refute_receive :notifications_changed

    publish(outcome)
    assert_receive :notifications_changed

    assert {:ok, {:created, []} = duplicate} = deliver(context, recipients)
    publish(duplicate)
    refute_receive :notifications_changed
    assert Repo.aggregate(Notification, :count) == 2
  end

  test "omits members whose access was removed and hides existing delivery after access loss", context do
    recipients = [%{user_id: context.direct.id, kind: "comment_reply"}]
    assert {:ok, {:created, [_]}} = deliver(context, recipients)
    scope = user_scope_fixture(context.direct)
    assert [_] = Platform.list_notifications(scope)

    membership =
      Repo.get_by!(Storyarn.Projects.ProjectMembership, project_id: context.project.id, user_id: context.direct.id)

    Repo.delete!(membership)

    assert Platform.list_notifications(scope) == []
    assert Platform.unread_notification_count(scope) == 0
    assert {:ok, {:created, []}} = deliver(%{context | comment_id: context.comment_id + 1}, recipients)
  end

  test "rejects an unauthorized actor and malformed producer recipients", context do
    assert {:error, :not_found} =
             deliver(%{context | actor: context.stranger}, [])

    assert {:error, :invalid_comment_activity} =
             deliver(context, [%{user_id: context.direct.id, kind: "content_created"}])

    assert {:error, :invalid_comment_activity} =
             deliver(context, [%{user_id: "123", kind: "comment_mention"}])

    assert Repo.aggregate(Notification, :count) == 0
  end

  test "requires the source transaction and rolls all notifications back with it", context do
    recipients = [%{user_id: context.direct.id, kind: "comment_mention"}]

    assert_raise ArgumentError, "deliver_comment_activity/4 must be called inside an open transaction", fn ->
      Platform.deliver_comment_activity(context.actor.id, context.project.id, context.comment_id, recipients)
    end

    assert {:error, :forced_rollback} =
             Repo.transact(fn ->
               assert {:ok, {:created, [_]}} = deliver(context, recipients)
               {:error, :forced_rollback}
             end)

    assert Repo.aggregate(Notification, :count) == 0
  end

  test "validates comment destinations as project-scoped and without async status", context do
    attrs = %{
      kind: "comment_mention",
      entity_type: "comment",
      entity_id: context.comment_id,
      dedupe_key: "comment-contract"
    }

    missing_project = Notification.create_changeset(%Notification{recipient_id: context.direct.id}, attrs)
    assert "is required for this entity type" in errors_on(missing_project).project_id

    with_status =
      Notification.create_changeset(
        %Notification{recipient_id: context.direct.id, project_id: context.project.id},
        Map.put(attrs, :status, "success")
      )

    assert "is only valid for asynchronous operations" in errors_on(with_status).status
  end

  defp deliver(context, recipients) do
    Repo.transact(fn ->
      Platform.deliver_comment_activity(context.actor.id, context.project.id, context.comment_id, recipients)
    end)
  end

  defp publish(outcome) do
    Platform.publish_notification_delivery(outcome)
  end
end
