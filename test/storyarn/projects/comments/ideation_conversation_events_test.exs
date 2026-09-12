defmodule Storyarn.Projects.IdeationConversationEventsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects

  setup do
    ideation_fixture()
  end

  test "private-mode changes do not invalidate another project's subscriber", ctx do
    outsider = user_scope_fixture()
    project_fixture(outsider.user)
    assert :ok = Projects.subscribe_ideation_conversations(outsider)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    refute_changed(ctx.project.id)
  end

  test "a direct member who also inherits access receives only one invalidation", ctx do
    project = Repo.preload(ctx.project, :workspace)
    workspace_membership_fixture(project.workspace, ctx.peer.user, "member")
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    assert_changed_once(ctx.project.id)
  end

  test "composing shell and Hub subscriptions does not duplicate source invalidations", ctx do
    assert :ok = Projects.subscribe_ideation_comment_source_changes(ctx.peer)
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    assert_changed_once(ctx.project.id)
  end

  test "inherited workspace viewers receive source invalidations without direct membership", ctx do
    inherited = user_scope_fixture()
    project = Repo.preload(ctx.project, :workspace)
    workspace_membership_fixture(project.workspace, inherited.user, "viewer")
    assert :ok = Projects.subscribe_ideation_conversations(inherited)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    assert_changed_once(ctx.project.id)
  end

  test "an existing user subscription follows current membership without reconnecting", ctx do
    newcomer = user_scope_fixture()
    assert :ok = Projects.subscribe_ideation_conversations(newcomer)
    Projects.invalidate_ideation_comment_sources(ctx.project.id)
    refute_changed(ctx.project.id)

    membership = membership_fixture(ctx.project, newcomer.user, "viewer")
    Projects.invalidate_ideation_comment_sources(ctx.project.id)
    assert_changed_once(ctx.project.id)

    Repo.delete!(membership)
    Projects.invalidate_ideation_comment_sources(ctx.project.id)
    refute_changed(ctx.project.id)
  end

  test "source invalidation cannot publish from an open transaction", ctx do
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, {:error, :comment_requires_outer_transaction}} =
             Repo.transaction(fn -> Projects.invalidate_ideation_comment_sources(ctx.project.id) end)

    refute_changed(ctx.project.id)
  end

  test "session renames refresh Hub labels but neither renames nor no-op edits invalidate inbox visibility", ctx do
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)
    project_id = ctx.project.id

    assert {:ok, renamed} =
             Ideation.update_session(ctx.facilitator, project_id, ctx.session.id, ctx.session.revision, %{
               title: "Renamed discussion"
             })

    assert_receive {:ideation_conversations_changed, ^project_id}
    refute_changed(project_id)

    assert {:ok, ^renamed} =
             Ideation.update_session(ctx.facilitator, project_id, ctx.session.id, renamed.revision, %{})

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, project_id, ctx.session.id, renamed.revision, false)

    refute_receive {:ideation_conversations_changed, ^project_id}
    refute_changed(project_id)
  end

  test "session creation, configuration and round controls leave inbox visibility unchanged", ctx do
    assert :ok = Projects.subscribe_ideation_comment_source_changes(ctx.peer)

    assert {:ok, _} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Another session"})

    assert {:ok, configured} =
             Ideation.update_session(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, %{
               objective: "A clearer goal"
             })

    assert {:ok, round_session} =
             Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, configured.revision, %{
               prompt: "Alternatives"
             })

    assert {:ok, _} =
             Ideation.set_contributions_open(
               ctx.facilitator,
               ctx.project.id,
               ctx.session.id,
               round_session.revision,
               false
             )

    refute_changed(ctx.project.id)
  end

  test "archiving only invalidates sources when it removes the private visibility mask", ctx do
    assert :ok = Projects.subscribe_ideation_comment_source_changes(ctx.peer)

    assert {:ok, archived} =
             Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision)

    refute_changed(ctx.project.id)
    assert {:ok, reopened} = Ideation.reopen_session(ctx.facilitator, ctx.project.id, ctx.session.id, archived.revision)
    refute_changed(ctx.project.id)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, reopened.revision, true)

    assert_changed_once(ctx.project.id)

    assert {:ok, masked} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, masked.revision)
    assert_changed_once(ctx.project.id)
  end

  test "timer expiry only invalidates sources when it actually reveals the private session", ctx do
    assert :ok = Projects.subscribe_ideation_comment_source_changes(ctx.peer)
    timer = start_timer(ctx, false)
    refute_changed(ctx.project.id)
    expire_timer(timer)
    refute_changed(ctx.project.id)

    assert {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, current.revision, true)
    assert_changed_once(ctx.project.id)
    revealing = start_timer(ctx, true)
    refute_changed(ctx.project.id)
    expire_timer(revealing)
    assert_changed_once(ctx.project.id)
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(revealing.id, revealing.version)
    refute_changed(ctx.project.id)
  end

  test "comment writes invalidate shared discussions and Hub activity without invalidating inbox sources", ctx do
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)
    assert :ok = Projects.subscribe_ideation_comments(ctx.peer, ctx.project.id, ctx.session.id)
    project_id = ctx.project.id
    session_id = ctx.session.id

    assert {:ok, detail} =
             Projects.create_ideation_comment(ctx.author, project_id, session_id, nil, %{
               body: "Shared discussion",
               client_request_id: Ecto.UUID.generate()
             })

    assert_receive {:ideation_conversations_changed, ^project_id}
    assert_receive {:ideation_comments_changed, ^session_id}
    refute_changed(project_id)

    assert {:ok, reply} =
             Projects.reply_to_comment_thread(ctx.peer, project_id, detail.thread.id, %{
               body: "Another perspective",
               parent_id: hd(detail.messages).id,
               client_request_id: Ecto.UUID.generate()
             })

    assert_receive {:ideation_conversations_changed, ^project_id}
    assert_receive {:ideation_comments_changed, ^session_id}
    refute_changed(project_id)

    assert {:ok, _} =
             Projects.set_comment_thread_status(
               ctx.author,
               project_id,
               detail.thread.id,
               "resolved",
               reply.thread.revision
             )

    assert_receive {:ideation_conversations_changed, ^project_id}
    assert_receive {:ideation_comments_changed, ^session_id}
    refute_changed(project_id)
  end

  test "shared canvas movements and connections do not invalidate conversation sources", ctx do
    {group, first, second} = group_fixture(ctx)
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, _} =
             Ideation.move_group(ctx.author, ctx.project.id, ctx.session.id, group.id, group.version, %{
               request_key: Ecto.UUID.generate(),
               x: 100,
               y: 200,
               member_versions: [%{id: first.id, version: 0}, %{id: second.id, version: 0}]
             })

    refute_changed(ctx.project.id)

    assert {:ok, %{"version" => 2}} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, first.id, 1, %{
               "request_key" => Ecto.UUID.generate(),
               "x" => 150,
               "y" => 300
             })

    refute_changed(ctx.project.id)

    assert {:ok, _} =
             Ideation.update_idea_connections(ctx.author, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               changes: [%{source_id: first.id, target_id: second.id, connected: true}],
               versions: [%{id: first.id, version: 0}]
             })

    refute_changed(ctx.project.id)
  end

  test "published idea deletion and restoration invalidate sources but retries do not", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, deleted} =
             Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, idea.revision)

    assert_changed_once(ctx.project.id)

    assert {:ok, ^deleted} =
             Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, idea.revision)

    refute_changed(ctx.project.id)

    assert {:ok, restored} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               deleted.revision,
               deleted.deleted_at
             )

    assert_changed_once(ctx.project.id)

    assert {:ok, ^restored} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               deleted.revision,
               deleted.deleted_at
             )

    refute_changed(ctx.project.id)
  end

  test "restoring an unpublished idea in private mode does not invalidate shared sources", ctx do
    idea = idea_fixture(ctx)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, deleted} =
             Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, idea.revision)

    refute_changed(ctx.project.id)

    assert {:ok, _restored} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               deleted.revision,
               deleted.deleted_at
             )

    refute_changed(ctx.project.id)
    assert {:ok, []} = Ideation.list_ideas(ctx.peer, ctx.project.id, ctx.session.id)
  end

  test "personal follow and read invalidations reach only the acting user's subscriptions", ctx do
    assert {:ok, detail} =
             Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, nil, %{
               body: "A shared discussion",
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: []
             })

    thread_id = detail.thread.id
    message_id = hd(detail.messages).id
    project_id = ctx.project.id
    session_id = ctx.session.id
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)
    assert :ok = Projects.subscribe_ideation_comments(ctx.peer, project_id, session_id)
    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, thread_id, true)
    refute_changed(ctx.project.id)
    refute_receive {:ideation_comments_changed, ^session_id}
    refute_receive {:ideation_comment_participation_changed, ^project_id, ^session_id, ^thread_id}
    assert {:ok, _} = Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, thread_id, message_id)
    refute_changed(ctx.project.id)
    refute_receive {:ideation_comments_changed, ^session_id}
    refute_receive {:ideation_comment_participation_changed, ^project_id, ^session_id, ^thread_id}

    assert :ok = Projects.subscribe_ideation_conversations(ctx.viewer)
    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, thread_id, false)
    assert_receive {:ideation_comment_participation_changed, ^project_id, ^session_id, ^thread_id}
    refute_changed(ctx.project.id)
    refute_receive {:ideation_comments_changed, ^session_id}
    assert {:ok, _} = Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, thread_id, message_id)
    assert_receive {:ideation_comment_participation_changed, ^project_id, ^session_id, ^thread_id}
    refute_changed(ctx.project.id)
    refute_receive {:ideation_comments_changed, ^session_id}
  end

  test "group deletion and restoration invalidate sources but retries do not", ctx do
    {group, _first, _second} = group_fixture(ctx)
    deletion_key = Ecto.UUID.generate()
    assert :ok = Projects.subscribe_ideation_conversations(ctx.peer)

    assert {:ok, deleted} =
             Ideation.delete_group(ctx.author, ctx.project.id, ctx.session.id, group.id, group.version, deletion_key)

    assert_changed_once(ctx.project.id)

    assert {:ok, ^deleted} =
             Ideation.delete_group(ctx.author, ctx.project.id, ctx.session.id, group.id, group.version, deletion_key)

    refute_changed(ctx.project.id)

    restore_attrs = %{
      request_key: Ecto.UUID.generate(),
      deleted_at: deleted.deleted_at,
      idea_ids: group.idea_ids
    }

    assert {:ok, restored} =
             Ideation.restore_group(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               group.id,
               deleted.version,
               restore_attrs
             )

    assert_changed_once(ctx.project.id)

    assert {:ok, ^restored} =
             Ideation.restore_group(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               group.id,
               deleted.version,
               restore_attrs
             )

    refute_changed(ctx.project.id)
  end

  defp assert_changed_once(project_id) do
    assert_receive {:ideation_comment_sources_changed, ^project_id}
    refute_changed(project_id)
  end

  defp refute_changed(project_id) do
    refute_receive {:ideation_comment_sources_changed, ^project_id}
  end

  defp start_timer(ctx, reveal) do
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    {:ok, _} =
      Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, %{
        seconds: 120,
        reveal_on_expiry: reveal
      })

    {:ok, timer} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
    timer
  end

  defp expire_timer(timer) do
    timer |> Ecto.Changeset.change(deadline_at: timer.started_at) |> Repo.update!()
    assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(timer.id, timer.version)
  end

  defp group_fixture(ctx) do
    first = idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => 20, "y" => 100, "width" => 280}})
    second = idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => 340, "y" => 100, "width" => 280}}, ctx.peer)

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Shared group",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    {group, first, second}
  end
end
