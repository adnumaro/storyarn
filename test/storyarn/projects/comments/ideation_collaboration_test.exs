defmodule Storyarn.Projects.IdeationCollaborationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.NotificationInbox
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Participation
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.ProjectMembership

  setup do
    ideation_fixture()
  end

  test "groups retain their conversation across soft restore but not replacement identities", ctx do
    group = group_fixture(ctx)
    assert {:ok, detail} = discuss(ctx, {:group, group.id}, [ctx.peer.user.id])
    assert detail.thread.source.type == "ideation_group"
    assert detail.thread.source.session_id == ctx.session.id
    refute inspect(detail) =~ "Unmaterialized synthesis"

    assert {:ok, %{threads: [thread]}} =
             Projects.list_ideation_comment_threads(ctx.viewer, ctx.project.id, ctx.session.id, {:group, group.id})

    assert thread.id == detail.thread.id
    assert {:ok, %{threads: [listed]}} = Projects.list_ideation_conversations(ctx.peer, source_type: "ideation_group")
    assert listed.id == thread.id

    assert {:ok, %{surface: "brainstorming"}} =
             Projects.comment_destination(ctx.peer, ctx.project.id, hd(detail.messages).id)

    assert {:ok, deleted} =
             Ideation.delete_group(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               group.id,
               group.version,
               Ecto.UUID.generate()
             )

    assert {:error, :not_found} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread.id)
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
    assert NotificationInbox.unread_notification_count(ctx.peer) == 0

    assert {:ok, _} =
             Ideation.restore_group(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               group.id,
               deleted.version,
               %{request_key: Ecto.UUID.generate(), deleted_at: deleted.deleted_at, idea_ids: group.idea_ids}
             )

    assert {:ok, _} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread.id)
    assert NotificationInbox.unread_notification_count(ctx.peer) == 1

    Group |> Repo.get!(group.id) |> Ecto.Changeset.change(recovery_identity: Ecto.UUID.generate()) |> Repo.update!()
    assert {:error, :not_found} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread.id)
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
    assert NotificationInbox.list_notifications(ctx.peer) == []
    Repo.delete!(Repo.get!(Group, group.id))
    assert is_nil(Repo.get!(Thread, thread.id).ideation_group_id)
    assert Projects.comment_destinations(ctx.peer, [hd(detail.messages).id]) == %{}
  end

  test "mentions, direct replies and explicit followers deliver once with strongest reason", ctx do
    assert {:ok, detail} = discuss(ctx, nil, [ctx.peer.user.id, ctx.author.user.id])
    assert [%{kind: "comment_mention"}] = NotificationInbox.list_notifications(ctx.peer)
    assert NotificationInbox.list_notifications(ctx.author) == []
    assert Repo.aggregate(Participation, :count) == 0

    assert {:ok, %{thread: %{following: true}}} =
             Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, detail.thread.id, true)

    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.author, ctx.project.id, detail.thread.id, true)
    request = reply_attrs(detail, [ctx.author.user.id])
    assert {:ok, _} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, detail.thread.id, request)
    assert {:ok, _} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, detail.thread.id, request)
    assert [%{kind: "comment_mention"}] = NotificationInbox.list_notifications(ctx.author)
    assert [%{kind: "comment_followed"}] = NotificationInbox.list_notifications(ctx.viewer)
    # Participation never auto-follows, and an unfollow does not mute mentions/direct replies.
    assert length(NotificationInbox.list_notifications(ctx.peer)) == 1
    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, detail.thread.id, false)
    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.author, ctx.project.id, detail.thread.id, false)
    assert {:ok, _} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, detail.thread.id, reply_attrs(detail))

    assert ctx.author |> NotificationInbox.list_notifications() |> Enum.map(& &1.kind) |> Enum.sort() == [
             "comment_mention",
             "comment_reply"
           ]

    assert length(NotificationInbox.list_notifications(ctx.viewer)) == 1

    assert {:ok, %{thread: %{following: false}}} =
             Projects.get_comment_thread(ctx.peer, ctx.project.id, detail.thread.id)
  end

  test "read watermarks are explicit, monotonic, scoped and do not acknowledge later replies", ctx do
    {:ok, detail} = discuss(ctx)
    id = detail.thread.id
    root_id = hd(detail.messages).id

    assert {:ok, %{thread: %{unread: true, following: false}}} =
             Projects.get_comment_thread(ctx.viewer, ctx.project.id, id)

    assert Repo.aggregate(Participation, :count) == 0

    assert {:ok, %{thread: %{unread: false}}} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, root_id)

    assert {:ok, latest} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, id, reply_attrs(detail))

    assert {:ok, %{thread: %{unread: true}}} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, root_id)

    assert {:ok, %{thread: %{unread: false}}} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, latest.thread.last_message_id)

    assert {:ok, %{thread: %{unread: false}}} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, root_id)

    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, id, true)

    assert {:ok, %{thread: %{unread: false, following: true}}} =
             Projects.get_comment_thread(ctx.viewer, ctx.project.id, id)

    {:ok, other} = discuss(ctx)

    assert {:error, :invalid_message} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, hd(other.messages).id)

    assert {:error, :invalid_message} = Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, id, "bad")
    assert {:error, :invalid_request} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, id, "true")

    assert {:error, :not_found} =
             Projects.set_ideation_comment_following(user_scope_fixture(), ctx.project.id, id, true)

    assert {:error, :not_found} = Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id + 1000, id, root_id)
  end

  test "private mode hides notifications, counters, Hub previews and personal mutations, not session discussions",
       ctx do
    group = group_fixture(ctx)
    idea = idea_fixture(ctx, %{visibility: :shared})
    {:ok, session_thread} = discuss(ctx, nil, [ctx.peer.user.id])
    {:ok, idea_thread} = discuss(ctx, idea.id, [ctx.peer.user.id])
    {:ok, group_thread} = discuss(ctx, {:group, group.id}, [ctx.peer.user.id])
    before_notifications = NotificationInbox.list_notifications(ctx.peer)
    assert length(before_notifications) == 3
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    project_id = ctx.project.id
    assert_receive {:ideation_comment_sources_changed, ^project_id}

    assert {:ok, %{threads: [visible]}} =
             Projects.list_ideation_conversations(ctx.peer, mentioned: true, search: "Discuss")

    assert visible.id == session_thread.thread.id
    assert NotificationInbox.unread_notification_count(ctx.peer) == 1
    assert [%{entity_id: message_id}] = NotificationInbox.list_notifications(ctx.peer)
    assert message_id == hd(session_thread.messages).id
    hidden = Enum.find(before_notifications, &(&1.entity_id == hd(idea_thread.messages).id))
    assert {:error, :not_found} = NotificationInbox.mark_notification_read(ctx.peer, hidden.id)

    for detail <- [idea_thread, group_thread] do
      assert {:error, :not_found} =
               Projects.set_ideation_comment_following(ctx.peer, ctx.project.id, detail.thread.id, true)

      assert {:error, :not_found} =
               Projects.mark_ideation_comment_read(ctx.peer, ctx.project.id, detail.thread.id, hd(detail.messages).id)

      assert Projects.comment_destinations(ctx.peer, [hd(detail.messages).id]) == %{}
    end

    assert {:ok, _} = NotificationInbox.mark_all_notifications_read(ctx.peer)
    assert is_nil(Repo.get!(Storyarn.Platform.Notifications.Notification, hidden.id).read_at)
  end

  test "Hub contract paginates stable activity ties with access and personal filters before limits", ctx do
    {:ok, first} = discuss(ctx, nil, [ctx.peer.user.id])
    {:ok, second} = discuss(ctx)
    {:ok, third} = discuss(ctx)
    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.peer, ctx.project.id, first.thread.id, true)

    assert {:ok, _} =
             Projects.mark_ideation_comment_read(ctx.peer, ctx.project.id, second.thread.id, hd(second.messages).id)

    assert {:ok, %{threads: [followed]}} = Projects.list_ideation_conversations(ctx.peer, following: true)
    assert followed.id == first.thread.id
    assert followed.project_id == ctx.project.id
    assert {:ok, %{threads: [mentioned]}} = Projects.list_ideation_conversations(ctx.peer, mentioned: true)
    assert mentioned.id == first.thread.id
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer, participated: true)
    assert {:ok, %{threads: unread}} = Projects.list_ideation_conversations(ctx.peer, unread: true)
    assert Enum.sort(Enum.map(unread, & &1.id)) == Enum.sort([first.thread.id, third.thread.id])
    assert {:ok, %{threads: [page_one], next_cursor: cursor}} = Projects.list_ideation_conversations(ctx.peer, limit: 1)
    assert page_one.id == third.thread.id

    assert {:ok, %{threads: [page_two], next_cursor: cursor_two}} =
             Projects.list_ideation_conversations(ctx.peer, limit: 1, cursor: cursor)

    assert page_two.id == second.thread.id

    assert {:ok, %{threads: [page_three], next_cursor: nil}} =
             Projects.list_ideation_conversations(ctx.peer, limit: 1, cursor: cursor_two)

    assert page_three.id == first.thread.id
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer, project_id: ctx.project.id + 999)
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(user_scope_fixture(), search: "Discuss", limit: 1)
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer, search: "absent")

    for opts <- [
          %{},
          [:bad],
          [project_id: "bad"],
          [limit: 0],
          [search: String.duplicate("x", 201)],
          [source_type: "private"],
          [unread: "yes"],
          [surprise: true]
        ] do
      assert {:error, :invalid_options} = Projects.list_ideation_conversations(ctx.peer, opts)
    end

    assert {:error, :invalid_cursor} = Projects.list_ideation_conversations(ctx.peer, cursor: %{at: "bad", id: 1})

    Repo.delete_all(
      from(m in ProjectMembership,
        where: m.project_id == ^ctx.project.id and m.user_id == ^ctx.peer.user.id
      )
    )

    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer, following: true)
    assert NotificationInbox.list_notifications(ctx.peer) == []
  end

  test "message-page read markers never advance through a message outside the returned page", ctx do
    {:ok, detail} = discuss(ctx)
    {:ok, latest} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, detail.thread.id, reply_attrs(detail))

    assert {:ok, page} =
             Projects.get_comment_thread(ctx.viewer, ctx.project.id, detail.thread.id,
               cursor: latest.thread.last_message_id,
               limit: 1
             )

    assert page.thread.last_message_id == hd(detail.messages).id
  end

  test "private contributions do not emit shared conversation activity", ctx do
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)
    idea_fixture(ctx, %{title: "Private working title"})
    project_id = ctx.project.id
    refute_receive {:ideation_comment_sources_changed, ^project_id}
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
  end

  test "inherited workspace viewers can discover shared discussions without direct membership", ctx do
    {:ok, detail} = discuss(ctx)
    inherited = user_scope_fixture()
    project = Repo.preload(ctx.project, :workspace)
    Storyarn.WorkspacesFixtures.workspace_membership_fixture(project.workspace, inherited.user, "viewer")

    assert {:ok, %{threads: [thread]}} =
             Projects.list_ideation_conversations(inherited,
               workspace_id: project.workspace.id,
               session_id: ctx.session.id,
               status: "all"
             )

    assert thread.id == detail.thread.id
    assert {:ok, _} = Projects.set_ideation_comment_following(inherited, project.id, thread.id, true)
    assert {:error, _} = Projects.create_ideation_comment(inherited, project.id, ctx.session.id, nil, attrs([]))
  end

  test "Hub pages batch source authorization regardless of size or membership type", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared, title: "Never expose the working title"})
    group = group_fixture(ctx)
    anchors = [nil, idea.id, {:group, group.id}]

    for index <- 0..29 do
      assert {:ok, _} = discuss(ctx, Enum.at(anchors, rem(index, 3)))
    end

    inherited = user_scope_fixture()
    project = Repo.preload(ctx.project, :workspace)
    Storyarn.WorkspacesFixtures.workspace_membership_fixture(project.workspace, inherited.user, "viewer")

    for scope <- [ctx.peer, inherited] do
      {one, single_count} = counted_hub_page(scope, limit: 1)
      {page, page_count} = counted_hub_page(scope, limit: 30)

      assert length(one.threads) == 1
      assert length(page.threads) == 30
      assert page_count == single_count
      assert page_count <= 8

      {panel_one, panel_single_count} = counted_source_page(ctx, scope, idea.id, limit: 1)
      {panel_page, panel_page_count} = counted_source_page(ctx, scope, idea.id, limit: 30)
      assert length(panel_one.threads) == 1
      assert length(panel_page.threads) == 10
      assert panel_page_count == panel_single_count
      assert panel_page_count <= 16

      labels = page.threads |> Enum.map(& &1.source.label) |> Enum.uniq() |> Enum.sort()
      assert labels == Enum.sort([ctx.session.title, "Idea ##{idea.id}", "Group ##{group.id}"])
      refute inspect(page) =~ "Never expose the working title"
      refute inspect(page) =~ "Unmaterialized synthesis"
    end
  end

  test "direct and inherited access do not duplicate Hub rows or cursor pages", ctx do
    project = Repo.preload(ctx.project, :workspace)
    Storyarn.WorkspacesFixtures.workspace_membership_fixture(project.workspace, ctx.peer.user, "viewer")
    {:ok, first} = discuss(ctx)
    {:ok, second} = discuss(ctx)

    assert {:ok, %{threads: threads, next_cursor: nil}} = Projects.list_ideation_conversations(ctx.peer)
    assert Enum.map(threads, & &1.id) == [second.thread.id, first.thread.id]

    assert {:ok, %{threads: [page_one], next_cursor: cursor}} =
             Projects.list_ideation_conversations(ctx.peer, limit: 1)

    assert page_one.id == second.thread.id
    assert cursor

    assert {:ok, %{threads: [page_two], next_cursor: nil}} =
             Projects.list_ideation_conversations(ctx.peer, limit: 1, cursor: cursor)

    assert page_two.id == first.thread.id
  end

  test "Hub search matches replies only within readable candidate threads", ctx do
    {:ok, matching} = discuss(ctx)
    {:ok, _other} = discuss(ctx)
    reply = matching |> reply_attrs() |> Map.put(:body, "Distinctive Hub search phrase")
    assert {:ok, _} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, matching.thread.id, reply)

    outsider = ideation_fixture()
    {:ok, outside_thread} = discuss(outsider)
    outside_reply = outside_thread |> reply_attrs() |> Map.put(:body, "Distinctive Hub search phrase")

    assert {:ok, _} =
             Projects.reply_to_comment_thread(
               outsider.peer,
               outsider.project.id,
               outside_thread.thread.id,
               outside_reply
             )

    assert {:ok, %{threads: [thread], next_cursor: nil}} =
             Projects.list_ideation_conversations(ctx.peer, search: "DISTINCTIVE hub", limit: 1)

    assert thread.id == matching.thread.id
  end

  test "a source hidden between authorization and serialization never falls back to a historical preview", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})
    {:ok, detail} = discuss(ctx, idea.id)

    for surface <- [:detail, :source_list, :hub] do
      set_source_private(ctx.session.id, false)
      marker = make_ref()
      Process.put(marker, true)

      :ok =
        :telemetry.attach(
          marker,
          [:storyarn, :repo, :query],
          &hide_source_during_read/4,
          {self(), marker, ctx.session.id}
        )

      try do
        assert_hidden_projection(surface, ctx, idea.id, detail.thread.id)
        refute Process.get(marker), "the visibility change must occur inside the read"
      after
        :telemetry.detach(marker)
        Process.delete(marker)
      end
    end
  end

  test "the Hub final batch rechecks membership after previews are loaded", ctx do
    {:ok, _detail} = discuss(ctx)
    marker = make_ref()
    Process.put(marker, true)

    :ok =
      :telemetry.attach(
        marker,
        [:storyarn, :repo, :query],
        &revoke_access_during_read/4,
        {self(), marker, ctx.project.id, ctx.peer.user.id}
      )

    try do
      assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
      refute Process.get(marker), "membership must be revoked inside the read"
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp assert_hidden_projection(:detail, ctx, _idea_id, thread_id) do
    assert {:error, :not_found} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread_id)
  end

  defp assert_hidden_projection(:source_list, ctx, idea_id, _thread_id) do
    assert {:ok, %{threads: []}} =
             Projects.list_ideation_comment_threads(ctx.peer, ctx.project.id, ctx.session.id, idea_id)
  end

  defp assert_hidden_projection(:hub, ctx, _idea_id, _thread_id) do
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
  end

  defp counted_hub_page(scope, opts), do: counted_page(fn -> Projects.list_ideation_conversations(scope, opts) end)

  defp counted_source_page(ctx, scope, anchor, opts) do
    counted_page(fn -> Projects.list_ideation_comment_threads(scope, ctx.project.id, ctx.session.id, anchor, opts) end)
  end

  defp counted_page(read) do
    marker = make_ref()
    Process.put(marker, 0)
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &count_query/4, {self(), marker})

    try do
      assert {:ok, page} = read.()
      {page, Process.get(marker)}
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp count_query(_event, _measurements, _metadata, {pid, marker}) do
    if self() == pid, do: Process.put(marker, Process.get(marker) + 1)
  end

  defp hide_source_during_read(_event, _measurements, %{query: query}, {pid, marker, session_id}) do
    if self() == pid and String.contains?(query, ~s(FROM "comment_messages")) and Process.delete(marker) do
      set_source_private(session_id, true)
    end
  end

  defp revoke_access_during_read(_event, _measurements, %{query: query}, {pid, marker, project_id, user_id}) do
    if self() == pid and String.contains?(query, ~s(FROM "comment_messages")) and Process.delete(marker) do
      Repo.delete_all(from(m in ProjectMembership, where: m.project_id == ^project_id and m.user_id == ^user_id))
    end
  end

  defp set_source_private(session_id, private?) do
    session = Repo.get!(Storyarn.Ideation.Sessions.Session, session_id)

    session
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:configuration, %{private_mode: private?})
    |> Repo.update!()
  end

  defp discuss(ctx, anchor \\ nil, mentions \\ []),
    do: Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, anchor, attrs(mentions))

  defp attrs(mentions),
    do: %{body: "Discuss this alternative", client_request_id: Ecto.UUID.generate(), mention_user_ids: mentions}

  defp reply_attrs(detail, mentions \\ []), do: Map.put(attrs(mentions), :parent_id, hd(detail.messages).id)

  defp group_fixture(ctx) do
    first = idea_fixture(ctx, %{visibility: :shared})
    second = idea_fixture(ctx, %{visibility: :shared}, ctx.peer)

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Shared group",
        synthesis: "Unmaterialized synthesis",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    group
  end
end
