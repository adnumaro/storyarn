defmodule Storyarn.NotificationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Notifications
  alias Storyarn.Notifications.Notification
  alias Storyarn.Repo

  describe "deliver/4" do
    test "stores, lists, deduplicates, and publishes a project notification" do
      owner = user_fixture()
      recipient = user_fixture()
      project = project_fixture(owner)
      membership_fixture(project, recipient)
      recipient_scope = user_scope_fixture(recipient)

      :ok = Notifications.subscribe(recipient_scope)

      assert {:ok, {:created, notification}} =
               Notifications.deliver(recipient_scope, owner, project, content_attrs("sheet:42:created"))

      assert notification.recipient_id == recipient.id
      assert notification.actor_id == owner.id
      assert notification.project_id == project.id
      assert notification.kind == "content_created"
      assert notification.entity_type == "sheet"
      assert notification.entity_id == 42
      assert notification.entity_name == "Main characters"
      assert is_nil(notification.read_at)

      refute_receive :notifications_changed
      assert :ok = publish_outside_transaction({:created, notification})
      assert_receive :notifications_changed

      assert [listed] = Notifications.list_notifications(recipient_scope)
      assert listed.id == notification.id
      assert Notifications.unread_count(recipient_scope) == 1

      assert {:ok, :deduplicated} =
               Notifications.deliver(recipient_scope, owner, project, content_attrs("sheet:42:created"))

      assert :ok = publish_outside_transaction(:deduplicated)
      refute_receive :notifications_changed
      assert Repo.aggregate(Notification, :count, :id) == 1
    end

    test "suppresses a notification produced by the recipient" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)

      assert {:ok, :suppressed} =
               Notifications.deliver(scope, user, project, content_attrs("sheet:42:created"))

      assert :ok = publish_outside_transaction(:suppressed)
      refute_receive :notifications_changed
      assert Repo.aggregate(Notification, :count, :id) == 0
    end

    test "allows the same dedupe key for different recipients" do
      owner = user_fixture()
      first = user_fixture()
      second = user_fixture()
      project = project_fixture(owner)
      membership_fixture(project, first)
      membership_fixture(project, second)
      attrs = content_attrs("sheet:42:created")

      assert {:ok, {:created, _notification}} =
               Notifications.deliver(user_scope_fixture(first), owner, project, attrs)

      assert {:ok, {:created, _notification}} =
               Notifications.deliver(user_scope_fixture(second), owner, project, attrs)

      assert Repo.aggregate(Notification, :count, :id) == 2
    end

    test "rejects project notifications when the recipient lacks current access" do
      owner = user_fixture()
      stranger = user_fixture()
      project = project_fixture(owner)

      assert {:error, :not_found} =
               Notifications.deliver(
                 user_scope_fixture(stranger),
                 owner,
                 project,
                 content_attrs("sheet:42:created")
               )

      assert Repo.aggregate(Notification, :count, :id) == 0
    end

    test "validates the small initial notification contract" do
      recipient = user_fixture()

      assert {:error, changeset} =
               Notifications.deliver(user_scope_fixture(recipient), nil, %{
                 kind: "async_operation",
                 entity_type: "template_install",
                 entity_id: 7,
                 dedupe_key: "snapshot:7:completed"
               })

      assert "is required for asynchronous operations" in errors_on(changeset).status
    end

    test "requires project context for project-scoped entity types" do
      recipient = user_fixture()

      assert {:error, changeset} =
               Notifications.deliver(user_scope_fixture(recipient), nil, %{
                 kind: "async_operation",
                 entity_type: "project_snapshot",
                 entity_id: 7,
                 status: "success",
                 dedupe_key: "snapshot:7:completed"
               })

      assert "is required for this entity type" in errors_on(changeset).project_id
    end
  end

  describe "deliver_async_result/3" do
    test "requires the source transaction and rolls delivery back with it" do
      recipient = user_fixture()
      project = project_fixture(recipient)
      scope = user_scope_fixture(recipient)

      attrs = %{
        entity_type: "project_snapshot",
        entity_id: 7,
        status: "success",
        dedupe_key: "project_snapshot:7:success"
      }

      assert_raise ArgumentError,
                   "deliver_async_result/3 must be called inside an open transaction",
                   fn -> Notifications.deliver_async_result(scope, project, attrs) end

      assert {:error, :forced_rollback} =
               Repo.transact(fn ->
                 assert {:ok, {:created, _notification}} =
                          Notifications.deliver_async_result(scope, project, attrs)

                 refute_receive :notifications_changed
                 {:error, :forced_rollback}
               end)

      assert Repo.aggregate(Notification, :count, :id) == 0
      refute_receive :notifications_changed
    end

    test "suppresses a missing requester only from inside the source transaction" do
      attrs = %{
        entity_type: "template_install",
        entity_id: 8,
        status: "failure",
        dedupe_key: "template_install:8:failure"
      }

      assert_raise ArgumentError,
                   "deliver_async_result/3 must be called inside an open transaction",
                   fn -> Notifications.deliver_async_result(nil, nil, attrs) end

      assert {:ok, {:ok, :suppressed}} =
               Repo.transaction(fn -> Notifications.deliver_async_result(nil, nil, attrs) end)
    end

    test "delivers the outcome only to its requester" do
      requester = user_fixture()
      teammate = user_fixture()
      project = project_fixture(requester)
      membership_fixture(project, teammate)
      requester_scope = user_scope_fixture(requester)
      teammate_scope = user_scope_fixture(teammate)

      attrs = %{
        entity_type: "project_import",
        entity_id: 9,
        status: "success",
        dedupe_key: "project_import:9:success"
      }

      :ok = Notifications.subscribe(requester_scope)
      :ok = Notifications.subscribe(teammate_scope)

      assert {:ok, {:ok, {:created, notification} = outcome}} =
               Repo.transaction(fn -> Notifications.deliver_async_result(requester_scope, project, attrs) end)

      assert notification.recipient_id == requester.id
      assert :ok = Notifications.publish_committed(outcome)
      assert_receive :notifications_changed
      refute_receive :notifications_changed
      assert Notifications.list_notifications(teammate_scope) == []
    end

    test "resolves scalar requester and project identities inside the source transaction" do
      requester = user_fixture()
      project = project_fixture(requester)

      attrs = %{
        entity_type: "localization_batch",
        entity_id: 10,
        status: "success",
        dedupe_key: "localization_batch:10:success"
      }

      assert_raise ArgumentError,
                   "deliver_async_result_by_ids/3 must be called inside an open transaction",
                   fn -> Notifications.deliver_async_result_by_ids(requester.id, project.id, attrs) end

      {lock_marker, lock_handler_id} = attach_scalar_lock_probe()
      on_exit(fn -> :telemetry.detach(lock_handler_id) end)

      assert {:ok, {:ok, {:created, notification}}} =
               Repo.transaction(fn ->
                 Notifications.deliver_async_result_by_ids(requester.id, project.id, attrs)
               end)

      assert_receive {^lock_marker, first_lock}
      assert_receive {^lock_marker, second_lock}
      assert [first_lock, second_lock] == [:project, :user]
      assert notification.recipient_id == requester.id
      assert notification.project_id == project.id
    end

    test "suppresses missing or unauthorized scalar identities" do
      owner = user_fixture()
      outsider = user_fixture()
      project = project_fixture(owner)

      attrs = %{
        entity_type: "localization_batch",
        entity_id: 11,
        status: "failure",
        dedupe_key: "localization_batch:11:failure"
      }

      assert {:ok, {:ok, :suppressed}} =
               Repo.transaction(fn ->
                 Notifications.deliver_async_result_by_ids(outsider.id, project.id, attrs)
               end)

      assert {:ok, {:ok, :suppressed}} =
               Repo.transaction(fn ->
                 Notifications.deliver_async_result_by_ids(nil, project.id, attrs)
               end)
    end
  end

  describe "deliver_to_project_members/3" do
    test "notifies every other effective member exactly once" do
      actor = user_fixture()
      direct_member = user_fixture()
      inherited_member = user_fixture()
      dual_member = user_fixture()
      stranger = user_fixture()
      workspace = workspace_fixture(actor)
      project = project_fixture(actor, %{workspace: workspace})

      membership_fixture(project, direct_member, "viewer")
      workspace_membership_fixture(workspace, inherited_member, "viewer")
      membership_fixture(project, dual_member)
      workspace_membership_fixture(workspace, dual_member)

      assert {:ok, {:created, notifications}} =
               Notifications.deliver_to_project_members(
                 user_scope_fixture(actor),
                 project,
                 content_attrs("flow:9:deleted", %{
                   kind: "content_deleted",
                   entity_type: "flow",
                   entity_id: 9,
                   entity_name: "Old tutorial"
                 })
               )

      assert notifications |> Enum.map(& &1.recipient_id) |> Enum.sort() ==
               Enum.sort([direct_member.id, inherited_member.id, dual_member.id])

      refute Enum.any?(notifications, &(&1.recipient_id in [actor.id, stranger.id]))

      assert {:ok, {:created, []}} =
               Notifications.deliver_to_project_members(
                 user_scope_fixture(actor),
                 project,
                 content_attrs("flow:9:deleted", %{
                   kind: "content_deleted",
                   entity_type: "flow",
                   entity_id: 9,
                   entity_name: "Old tutorial"
                 })
               )

      assert Repo.aggregate(Notification, :count, :id) == 3
    end

    test "rejects fan-out from an actor without project access" do
      owner = user_fixture()
      stranger = user_fixture()
      project = project_fixture(owner)

      assert {:error, :not_found} =
               Notifications.deliver_to_project_members(
                 user_scope_fixture(stranger),
                 project,
                 content_attrs("sheet:42:created")
               )

      assert Repo.aggregate(Notification, :count, :id) == 0
    end

    test "returns a validation error for an all-whitespace dedupe key" do
      actor = user_fixture()
      recipient = user_fixture()
      project = project_fixture(actor)
      membership_fixture(project, recipient)

      assert {:error, changeset} =
               Notifications.deliver_to_project_members(
                 user_scope_fixture(actor),
                 project,
                 content_attrs("   ")
               )

      assert "can't be blank" in errors_on(changeset).dedupe_key
      assert Repo.aggregate(Notification, :count, :id) == 0
    end
  end

  describe "deliver_content_activity/5" do
    test "accepts scalar actor and project identities for isolated contexts" do
      actor = user_fixture()
      recipient = user_fixture()
      project = project_fixture(actor)
      membership_fixture(project, recipient)
      entity_id = System.unique_integer([:positive])

      assert_raise ArgumentError,
                   "deliver_content_activity_by_ids/5 must be called inside an open transaction",
                   fn ->
                     Notifications.deliver_content_activity_by_ids(
                       actor.id,
                       project.id,
                       :created,
                       "localization_language",
                       %{id: entity_id, name: "Danish"}
                     )
                   end

      {lock_marker, lock_handler_id} = attach_scalar_lock_probe()
      on_exit(fn -> :telemetry.detach(lock_handler_id) end)

      assert {:ok, {:ok, {:created, [notification]}}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity_by_ids(
                   actor.id,
                   project.id,
                   :created,
                   "localization_language",
                   %{id: entity_id, name: "Danish"}
                 )
               end)

      assert_receive {^lock_marker, first_lock}
      assert_receive {^lock_marker, second_lock}
      assert [first_lock, second_lock] == [:project, :user]
      assert notification.recipient_id == recipient.id
      assert notification.actor_id == actor.id
      assert notification.project_id == project.id
      assert notification.entity_type == "localization_language"
      assert notification.entity_id == entity_id
    end

    test "requires the source transaction and stores the structural event contract once" do
      actor = user_fixture()
      recipient = user_fixture()
      project = project_fixture(actor)
      membership_fixture(project, recipient)
      actor_scope = user_scope_fixture(actor)
      recipient_scope = user_scope_fixture(recipient)

      assert_raise ArgumentError,
                   "deliver_content_activity/5 must be called inside an open transaction",
                   fn ->
                     Notifications.deliver_content_activity(
                       actor_scope,
                       project,
                       :created,
                       "sheet",
                       %{id: 42, name: "Main characters"}
                     )
                   end

      :ok = Notifications.subscribe(recipient_scope)

      assert {:ok, {:ok, {:created, [notification]} = outcome}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   actor_scope,
                   project,
                   :created,
                   "sheet",
                   %{id: 42, name: "Main characters"}
                 )
               end)

      assert notification.recipient_id == recipient.id
      assert notification.actor_id == actor.id
      assert notification.project_id == project.id
      assert notification.kind == "content_created"
      assert notification.entity_type == "sheet"
      assert notification.entity_id == 42
      assert notification.entity_name == "Main characters"

      assert notification.dedupe_key ==
               "structural-content:v1:#{project.id}:sheet:42:created"

      refute_receive :notifications_changed
      assert :ok = Notifications.publish_committed(outcome)
      assert_receive :notifications_changed

      assert {:ok, {:ok, {:created, []} = duplicate_outcome}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   actor_scope,
                   project,
                   :created,
                   "sheet",
                   %{id: 42, name: "Changed retry payload"}
                 )
               end)

      assert :ok = Notifications.publish_committed(duplicate_outcome)
      refute_receive :notifications_changed
      assert Repo.aggregate(Notification, :count, :id) == 1
    end

    test "rolls delivery back with its source transaction" do
      actor = user_fixture()
      recipient = user_fixture()
      project = project_fixture(actor)
      membership_fixture(project, recipient)
      actor_scope = user_scope_fixture(actor)
      recipient_scope = user_scope_fixture(recipient)
      :ok = Notifications.subscribe(recipient_scope)

      assert {:error, :forced_rollback} =
               Repo.transact(fn ->
                 assert {:ok, {:created, [_notification]}} =
                          Notifications.deliver_content_activity(
                            actor_scope,
                            project,
                            :deleted,
                            "flow",
                            %{id: 9, name: "Old tutorial"}
                          )

                 refute_receive :notifications_changed
                 {:error, :forced_rollback}
               end)

      assert Repo.aggregate(Notification, :count, :id) == 0
      assert content_activity_marker_count(project, "flow", 9, :deleted) == 0
      refute_receive :notifications_changed
    end

    test "claims an event with no recipients and suppresses a retry after a member joins" do
      actor = user_fixture()
      project = project_fixture(actor)
      actor_scope = user_scope_fixture(actor)
      entity_id = System.unique_integer([:positive])

      assert {:ok, {:ok, {:created, []} = first_outcome}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   actor_scope,
                   project,
                   :created,
                   "sheet",
                   %{id: entity_id, name: "Initially private"}
                 )
               end)

      assert content_activity_marker_count(project, "sheet", entity_id, :created) == 1
      assert :ok = Notifications.publish_committed(first_outcome)

      late_member = user_fixture()
      membership_fixture(project, late_member, "viewer")
      late_scope = user_scope_fixture(late_member)
      :ok = Notifications.subscribe(late_scope)

      assert {:ok, {:ok, {:created, []} = retry_outcome}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   actor_scope,
                   project,
                   :created,
                   "sheet",
                   %{id: entity_id, name: "Changed retry payload"}
                 )
               end)

      assert :ok = Notifications.publish_committed(retry_outcome)
      refute_receive :notifications_changed
      assert content_activity_marker_count(project, "sheet", entity_id, :created) == 1

      dedupe_key = "structural-content:v1:#{project.id}:sheet:#{entity_id}:created"

      assert Repo.aggregate(
               from(notification in Notification,
                 where: notification.dedupe_key == ^dedupe_key
               ),
               :count,
               :id
             ) == 0
    end

    test "authorizes and validates before claiming an event" do
      owner = user_fixture()
      outsider_scope = user_scope_fixture(user_fixture())
      project = project_fixture(owner)
      owner_scope = user_scope_fixture(owner)
      unauthorized_entity_id = System.unique_integer([:positive])
      invalid_entity_id = System.unique_integer([:positive])

      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   outsider_scope,
                   project,
                   :created,
                   "scene",
                   %{id: unauthorized_entity_id, name: "Unauthorized"}
                 )
               end)

      assert content_activity_marker_count(
               project,
               "scene",
               unauthorized_entity_id,
               :created
             ) == 0

      assert {:ok, {:error, changeset}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   owner_scope,
                   project,
                   :created,
                   "scene",
                   %{id: invalid_entity_id, name: String.duplicate("x", 256)}
                 )
               end)

      assert "should be at most 255 character(s)" in errors_on(changeset).entity_name
      assert content_activity_marker_count(project, "scene", invalid_entity_id, :created) == 0

      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn ->
                 Notifications.deliver_content_activity(
                   %Scope{},
                   project,
                   :created,
                   "scene",
                   %{id: System.unique_integer([:positive]), name: "Missing actor"}
                 )
               end)
    end
  end

  describe "recipient-scoped reads" do
    test "lists only the recipient's visible notifications in stable newest-first order" do
      owner = user_fixture()
      recipient = user_fixture()
      other = user_fixture()
      project = project_fixture(owner)
      membership = membership_fixture(project, recipient)

      {:ok, {:created, older}} =
        Notifications.deliver(
          user_scope_fixture(recipient),
          owner,
          project,
          content_attrs("sheet:1:created", %{entity_id: 1})
        )

      {:ok, {:created, newer}} =
        Notifications.deliver(
          user_scope_fixture(recipient),
          owner,
          project,
          content_attrs("sheet:2:created", %{entity_id: 2})
        )

      {:ok, {:created, _other_notification}} =
        Notifications.deliver(user_scope_fixture(other), nil, async_attrs("snapshot:3:success"))

      assert Enum.map(Notifications.list_notifications(user_scope_fixture(recipient)), & &1.id) == [
               newer.id,
               older.id
             ]

      Repo.delete!(membership)

      assert Notifications.list_notifications(user_scope_fixture(recipient)) == []
      assert Notifications.unread_count(user_scope_fixture(recipient)) == 0
      assert {:error, :not_found} = Notifications.mark_read(user_scope_fixture(recipient), older.id)
    end

    test "filters unread notifications and caps an explicit list limit" do
      recipient = user_fixture()
      scope = user_scope_fixture(recipient)

      {:ok, {:created, first}} = Notifications.deliver(scope, nil, async_attrs("snapshot:1:success"))
      {:ok, {:created, second}} = Notifications.deliver(scope, nil, async_attrs("snapshot:2:success"))
      assert {:ok, _read} = Notifications.mark_read(scope, first.id)

      assert [listed] = Notifications.list_notifications(scope, unread_only: true, limit: 1)
      assert listed.id == second.id
      assert Notifications.unread_count(scope) == 1
    end
  end

  describe "read state" do
    test "marks one notification idempotently without allowing another user to mutate it" do
      recipient = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(recipient)
      {:ok, {:created, notification}} = Notifications.deliver(scope, nil, async_attrs("snapshot:1:success"))

      :ok = Notifications.subscribe(scope)

      assert {:error, :not_found} = Notifications.mark_read(user_scope_fixture(other), notification.id)
      refute_receive :notifications_changed

      assert {:ok, read} = Notifications.mark_read(scope, notification.id)
      assert %DateTime{} = read.read_at
      assert_receive :notifications_changed
      assert Notifications.unread_count(scope) == 0

      assert {:ok, same_read} = Notifications.mark_read(scope, notification.id)
      assert same_read.read_at == read.read_at
      refute_receive :notifications_changed
    end

    test "marks all current notifications for only the scoped recipient" do
      recipient = user_fixture()
      other = user_fixture()
      scope = user_scope_fixture(recipient)

      {:ok, {:created, first}} = Notifications.deliver(scope, nil, async_attrs("snapshot:1:success"))
      {:ok, {:created, second}} = Notifications.deliver(scope, nil, async_attrs("snapshot:2:failure", "failure"))

      {:ok, {:created, other_notification}} =
        Notifications.deliver(user_scope_fixture(other), nil, async_attrs("snapshot:3:success"))

      :ok = Notifications.subscribe(scope)

      assert {:ok, 2} = Notifications.mark_all_read(scope)
      assert_receive :notifications_changed
      assert Notifications.unread_count(scope) == 0
      assert Repo.get!(Notification, first.id).read_at
      assert Repo.get!(Notification, second.id).read_at
      assert is_nil(Repo.get!(Notification, other_notification.id).read_at)

      assert {:ok, 0} = Notifications.mark_all_read(scope)
      refute_receive :notifications_changed
    end

    test "rejects read mutations inside an open transaction" do
      recipient = user_fixture()
      scope = user_scope_fixture(recipient)

      {:ok, {:created, notification}} =
        Notifications.deliver(scope, nil, async_attrs("template-install:read-guard:success"))

      :ok = Notifications.subscribe(scope)

      assert_raise ArgumentError,
                   "mark_read/2 must be called outside an open transaction",
                   fn ->
                     Repo.transact(fn ->
                       Notifications.mark_read(scope, notification.id)
                       {:ok, :read}
                     end)
                   end

      assert_raise ArgumentError,
                   "mark_all_read/1 must be called outside an open transaction",
                   fn ->
                     Repo.transact(fn ->
                       Notifications.mark_all_read(scope)
                       {:ok, :read}
                     end)
                   end

      assert Notifications.unread_count(scope) == 1
      refute_receive :notifications_changed
    end
  end

  test "a rolled-back source transaction leaves no notification and no invalidation" do
    recipient = user_fixture()
    scope = user_scope_fixture(recipient)
    :ok = Notifications.subscribe(scope)

    assert {:error, :forced_rollback} =
             Repo.transact(fn ->
               assert {:ok, {:created, _notification}} =
                        Notifications.deliver(scope, nil, async_attrs("snapshot:1:success"))

               refute_receive :notifications_changed
               {:error, :forced_rollback}
             end)

    assert Repo.aggregate(Notification, :count, :id) == 0
    refute_receive :notifications_changed
  end

  test "publishing from an open producer transaction is rejected" do
    recipient = user_fixture()
    scope = user_scope_fixture(recipient)
    :ok = Notifications.subscribe(scope)

    {:ok, {:created, notification}} =
      Notifications.deliver(scope, nil, async_attrs("template-install:1:success"))

    assert_raise ArgumentError,
                 "publish_committed/1 must be called outside an open transaction",
                 fn ->
                   Repo.transact(fn ->
                     Notifications.publish_committed({:created, notification})
                     {:ok, :published}
                   end)
                 end

    refute_receive :notifications_changed
  end

  test "deleting the actor nilifies it and deleting the recipient or project cascades" do
    project_owner = user_fixture()
    actor = user_fixture()
    actor_workspace = workspace_fixture(actor)
    recipient = user_fixture()
    project = project_fixture(project_owner)
    membership_fixture(project, actor)
    membership_fixture(project, recipient)
    scope = user_scope_fixture(recipient)

    {:ok, {:created, actor_notification}} =
      Notifications.deliver(scope, actor, project, content_attrs("sheet:1:created", %{entity_id: 1}))

    Repo.delete!(actor_workspace)
    Repo.delete!(actor)
    assert is_nil(Repo.get!(Notification, actor_notification.id).actor_id)

    second_project_owner = user_fixture()
    project_to_delete = project_fixture(second_project_owner)
    membership_fixture(project_to_delete, recipient)

    {:ok, {:created, project_notification}} =
      Notifications.deliver(
        scope,
        second_project_owner,
        project_to_delete,
        content_attrs("sheet:2:created", %{entity_id: 2})
      )

    Repo.delete!(project_to_delete)
    refute Repo.get(Notification, project_notification.id)

    personal_recipient = user_fixture()
    personal_workspace = workspace_fixture(personal_recipient)

    {:ok, {:created, personal_notification}} =
      Notifications.deliver(
        user_scope_fixture(personal_recipient),
        nil,
        async_attrs("snapshot:3:success")
      )

    Repo.delete!(personal_workspace)
    Repo.delete!(personal_recipient)
    refute Repo.get(Notification, personal_notification.id)
  end

  defp content_attrs(dedupe_key, overrides \\ %{}) do
    Map.merge(
      %{
        kind: "content_created",
        entity_type: "sheet",
        entity_id: 42,
        entity_name: "Main characters",
        dedupe_key: dedupe_key
      },
      overrides
    )
  end

  defp async_attrs(dedupe_key, status \\ "success") do
    %{
      kind: "async_operation",
      entity_type: "template_install",
      entity_id: System.unique_integer([:positive]),
      status: status,
      dedupe_key: dedupe_key
    }
  end

  defp content_activity_marker_count(project, entity_type, entity_id, action) do
    action = Atom.to_string(action)

    Repo.one(
      from(marker in "notification_content_activity_markers",
        where:
          field(marker, :project_id) == ^project.id and
            field(marker, :entity_type) == ^entity_type and
            field(marker, :entity_id) == ^entity_id and
            field(marker, :action) == ^action,
        select: count(field(marker, :id))
      )
    )
  end

  defp attach_scalar_lock_probe do
    handler_id = "notification-scalar-lock-order-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        &handle_scalar_lock_query/4,
        {test_pid, marker}
      )

    {marker, handler_id}
  end

  defp handle_scalar_lock_query(_event, _measurements, %{query: query}, {pid, marker}) do
    if self() == pid do
      cond do
        String.contains?(query, ~s(FROM "projects")) and String.contains?(query, "FOR SHARE") ->
          send(pid, {marker, :project})

        String.contains?(query, ~s(FROM "users")) and String.contains?(query, "FOR KEY SHARE") ->
          send(pid, {marker, :user})

        true ->
          :ok
      end
    end
  end

  defp publish_outside_transaction(outcome) do
    fn -> Notifications.publish_committed(outcome) end
    |> Task.async()
    |> Task.await()
  end
end
