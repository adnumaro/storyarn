defmodule Storyarn.Projects.IdeationDecisionCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.NotificationInbox
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Thread

  setup do
    ctx = ideation_fixture()
    idea = idea_fixture(ctx, %{visibility: :shared, title: "Shared direction", body: "<p>Original basis</p>"})
    ctx = Map.put(ctx, :idea, idea)
    {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, decision_attrs(ctx))
    Map.put(ctx, :decision, decision)
  end

  test "a decision's discussion is a positionless ideation thread every project reader can follow", ctx do
    anchor = {:decision, ctx.decision.id}
    assert {:ok, detail} = discuss(ctx, anchor, [ctx.peer.user.id])
    assert %{type: "ideation_decision", id: id, session_id: session_id} = detail.thread.source
    assert id == ctx.decision.id
    assert session_id == ctx.session.id
    assert is_nil(detail.thread.position)

    thread = Repo.get!(Thread, detail.thread.id)
    assert thread.ideation_decision_id == ctx.decision.id
    assert is_nil(thread.ideation_idea_id) and is_nil(thread.ideation_group_id)
    assert thread.source_label == "Decision"

    assert {:ok, %{threads: [listed]}} =
             Projects.list_ideation_comment_threads(ctx.viewer, ctx.project.id, ctx.session.id, anchor)

    assert listed.id == detail.thread.id

    assert {:ok, %{threads: []}} =
             Projects.list_ideation_comment_threads(ctx.viewer, ctx.project.id, ctx.session.id, ctx.idea.id)

    assert {:ok, pins} = Projects.list_ideation_comment_pins(ctx.viewer, ctx.project.id, ctx.session.id)
    assert Enum.map(pins, & &1.source.type) == ["ideation_decision"]

    assert {:ok, %{threads: [hub]}} = Projects.list_ideation_conversations(ctx.peer, source_type: "ideation_decision")
    assert hub.id == detail.thread.id
    assert [%{kind: "comment_mention"}] = NotificationInbox.list_notifications(ctx.peer)

    assert {:ok, %{surface: "brainstorming", session_id: ^session_id}} =
             Projects.comment_destination(ctx.peer, ctx.project.id, hd(detail.messages).id)
  end

  test "the discussion never takes a canvas position", ctx do
    anchor = {:decision, ctx.decision.id}

    assert {:error, :invalid_request} =
             Projects.create_ideation_comment(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               anchor,
               Map.put(attrs([]), :position, %{x: 10, y: 20})
             )

    assert {:ok, detail} = discuss(ctx, anchor)

    assert {:error, :invalid_position} =
             Projects.move_comment_thread(
               ctx.author,
               ctx.project.id,
               detail.thread.id,
               %{x: 10, y: 20},
               detail.thread.revision
             )
  end

  test "resolving the discussion leaves the decision alone and retiring the decision keeps it", ctx do
    assert {:ok, detail} = discuss(ctx, {:decision, ctx.decision.id})

    assert {:ok, %{status: "resolved"}} =
             Projects.set_comment_thread_status(
               ctx.author,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               detail.thread.revision
             )

    assert Repo.get!(Decision, ctx.decision.id).status == :proposed

    assert {:ok, _} =
             Ideation.withdraw_decision(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.decision.id,
               ctx.decision.version,
               Ecto.UUID.generate()
             )

    assert {:ok, %{thread: %{status: "resolved"}}} =
             Projects.get_comment_thread(ctx.viewer, ctx.project.id, detail.thread.id)
  end

  test "a decision anchors only its own session's discussions", ctx do
    {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Another session"})

    assert {:error, :not_found} =
             Projects.create_ideation_comment(
               ctx.author,
               ctx.project.id,
               other.id,
               {:decision, ctx.decision.id},
               attrs([])
             )

    assert {:error, :not_found} = discuss(ctx, {:decision, ctx.decision.id + 1_000_000})
  end

  test "a replaced decision identity makes its discussion unavailable", ctx do
    assert {:ok, detail} = discuss(ctx, {:decision, ctx.decision.id})

    Decision
    |> Repo.get!(ctx.decision.id)
    |> Ecto.Changeset.change(recovery_identity: Ecto.UUID.generate())
    |> Repo.update!()

    assert {:error, :not_found} = Projects.get_comment_thread(ctx.peer, ctx.project.id, detail.thread.id)
    assert {:ok, %{threads: []}} = Projects.list_ideation_conversations(ctx.peer)
    assert NotificationInbox.list_notifications(ctx.peer) == []
  end

  defp discuss(ctx, anchor, mentions \\ []),
    do: Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, anchor, attrs(mentions))

  defp attrs(mentions),
    do: %{body: "Does this hold in act two?", client_request_id: Ecto.UUID.generate(), mention_user_ids: mentions}

  defp decision_attrs(ctx) do
    {:ok, sources} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: ctx.idea.id}])

    %{
      title: "Choose a direction",
      conclusion: "Keep the original direction",
      verb: "change",
      targets: [],
      responsible_id: ctx.peer.user.id,
      sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
      request_key: Ecto.UUID.generate()
    }
  end
end
