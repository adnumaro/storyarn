defmodule Storyarn.Projects.IdeationCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread

  setup do
    ideation_fixture()
  end

  test "session conversation creates and replies idempotently with revision-safe resolution", ctx do
    attrs = attrs()
    assert :ok = Projects.subscribe_ideation_comments(ctx.peer, ctx.project.id, ctx.session.id)
    assert {:ok, first} = create(ctx, nil, attrs)
    session_id = ctx.session.id
    assert_receive {:ideation_comments_changed, ^session_id}
    assert {:ok, repeated} = create(ctx, nil, attrs)
    assert first.thread.id == repeated.thread.id
    refute_receive {:ideation_comments_changed, _}
    assert Repo.aggregate(Message, :count) == 1
    assert {:error, :idempotency_conflict} = create(ctx, nil, %{attrs | body: "Other payload"})

    reply = Map.put(attrs(), :parent_id, hd(first.messages).id)
    assert {:ok, second} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, first.thread.id, reply)
    assert {:ok, repeated_reply} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, first.thread.id, reply)
    assert length(repeated_reply.messages) == 2

    assert {:error, :stale} =
             Projects.set_comment_thread_status(
               ctx.author,
               ctx.project.id,
               first.thread.id,
               "resolved",
               first.thread.revision
             )

    assert {:ok, resolved} =
             Projects.set_comment_thread_status(
               ctx.author,
               ctx.project.id,
               first.thread.id,
               "resolved",
               second.thread.revision
             )

    assert {:error, :thread_resolved} =
             Projects.reply_to_comment_thread(
               ctx.peer,
               ctx.project.id,
               first.thread.id,
               Map.put(attrs(), :parent_id, hd(first.messages).id)
             )

    assert {:ok, %{status: "open"}} =
             Projects.set_comment_thread_status(ctx.author, ctx.project.id, first.thread.id, "open", resolved.revision)

    assert {:ok, %{threads: [_]}} = Projects.list_ideation_comment_threads(ctx.viewer, ctx.project.id, ctx.session.id)
    assert Storyarn.Platform.list_notifications(ctx.author) == []
  end

  test "private ideas cannot be discussed even by their author or owner", ctx do
    idea = idea_fixture(ctx, %{title: "Do not reveal"})

    for scope <- [ctx.owner, ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, _} = Projects.create_ideation_comment(scope, ctx.project.id, ctx.session.id, idea.id, attrs())
      assert {:error, :not_found} = Projects.list_ideation_comment_threads(scope, ctx.project.id, ctx.session.id, idea.id)
    end

    assert Repo.aggregate(Thread, :count) == 0
  end

  test "shared anchors never use private title edits and disappear in private mode including retries", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    attrs = attrs()
    assert {:ok, discussion} = create(ctx, idea.id, attrs)

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               idea.revision,
               edit_attrs(%{title: "Secret unpublished title"})
             )

    assert {:ok, visible} = Projects.get_comment_thread(ctx.peer, ctx.project.id, discussion.thread.id)
    refute inspect(visible) =~ "Secret unpublished"

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    for scope <- [ctx.owner, ctx.author, ctx.peer] do
      assert {:error, :not_found} = Projects.get_comment_thread(scope, ctx.project.id, discussion.thread.id)
      assert {:error, :not_found} = Projects.list_ideation_comment_threads(scope, ctx.project.id, ctx.session.id, idea.id)

      assert {:error, _} =
               Projects.reply_to_comment_thread(
                 scope,
                 ctx.project.id,
                 discussion.thread.id,
                 Map.put(attrs(), :parent_id, hd(discussion.messages).id)
               )

      assert {:error, _} =
               Projects.set_comment_thread_status(
                 scope,
                 ctx.project.id,
                 discussion.thread.id,
                 "resolved",
                 discussion.thread.revision
               )
    end

    assert {:error, :not_found} = create(ctx, idea.id, attrs)
    assert {:ok, _} = create(ctx, nil, attrs())
    assert Repo.aggregate(Message, :count) == 2
  end

  test "viewer, revoked and cross-project access cannot mutate or discover", ctx do
    {:ok, discussion} = create(ctx, nil, attrs())
    outsider = user_scope_fixture()
    assert {:error, :not_found} = Projects.get_comment_thread(outsider, ctx.project.id, discussion.thread.id)
    assert {:error, _} = Projects.create_ideation_comment(ctx.viewer, ctx.project.id, ctx.session.id, nil, attrs())

    assert {:error, _} =
             Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id + 10_000, nil, attrs())

    Repo.delete_all(
      from(m in Storyarn.Projects.ProjectMembership,
        where: m.project_id == ^ctx.project.id and m.user_id == ^ctx.author.user.id
      )
    )

    assert {:error, :not_found} = Projects.get_comment_thread(ctx.author, ctx.project.id, discussion.thread.id)
    assert {:error, _} = create(ctx, nil, attrs())
  end

  test "hard deletion leaves an inaccessible tombstone and legacy APIs do not expose it", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    {:ok, discussion} = create(ctx, idea.id, attrs())
    assert {:ok, %{threads: []}} = Projects.list_flow_comment_threads(ctx.peer, ctx.project.id, ctx.session.id)
    assert %{} = Projects.comment_destinations(ctx.peer, [hd(discussion.messages).id])
    assert {:error, :not_found} = Projects.comment_destination(ctx.peer, ctx.project.id, hd(discussion.messages).id)
    Repo.delete!(Repo.get!(Idea, idea.id))
    assert Repo.get!(Thread, discussion.thread.id).ideation_idea_id == nil
    assert {:error, :not_found} = Projects.get_comment_thread(ctx.author, ctx.project.id, discussion.thread.id)
    assert Repo.aggregate(Message, :count) == 1
  end

  test "mentions and spatial moves are explicitly disabled", ctx do
    assert {:error, _} = create(ctx, nil, Map.put(attrs(), :mention_user_ids, [ctx.peer.user.id]))
    {:ok, discussion} = create(ctx, nil, attrs())

    assert {:error, :invalid_mention} =
             Projects.reply_to_comment_thread(
               ctx.author,
               ctx.project.id,
               discussion.thread.id,
               Map.merge(attrs(), %{parent_id: hd(discussion.messages).id, mention_user_ids: [ctx.peer.user.id]})
             )

    assert {:error, :invalid_position} =
             Projects.move_comment_thread(
               ctx.author,
               ctx.project.id,
               discussion.thread.id,
               %{x: 1, y: 1},
               discussion.thread.revision
             )
  end

  defp create(ctx, idea_id, attrs),
    do: Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, idea_id, attrs)

  defp attrs, do: %{body: "Discuss this alternative", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}
end
