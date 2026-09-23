defmodule StoryarnWeb.IdeationLive.DecisionsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()

    idea =
      idea_fixture(ctx, %{title: "A quieter ending", body: "<p>The player chooses to stay.</p>", visibility: :shared})

    ctx |> Map.put(:idea, idea) |> Map.update!(:project, &Repo.preload(&1, :workspace))
  end

  test "a selected shared idea becomes a proposal for the session's responsible editor", ctx do
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    assert state(view)["mode"] == "create"
    assert [%{"preview" => "The player chooses to stay.", "available" => true}] = state(view)["sources"]
    assert state(view)["defaultOwnerId"] == ctx.facilitator.user.id
    refute Enum.any?(state(view)["members"], &(&1["id"] == ctx.viewer.user.id))

    act(view, ctx, "create", proposal(view, ctx))
    selected = state(view)["selected"]
    assert selected["proposal"]["title"] == "Keep the ending quiet"
    assert selected["proposal"]["verb"] == "change"
    assert selected["status"] == "proposed"
    refute selected["canAccept"]
    assert selected["proposal"]["responsibleId"] == ctx.facilitator.user.id
    assert selected["accepted"] == nil
    assert {:ok, unchanged} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id)
    assert unchanged.body == ctx.idea.body
  end

  test "background entry points keep an existing proposal and its editing context", ctx do
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    original = state(view)

    act(view, ctx, "open", %{from_header: true})
    assert state(view)["context"] == original["context"]
    assert state(view)["mode"] == "create"

    for event <- ["decisions_new", "comments_open", "references_open"] do
      render_hook(view, event, payload(view, ctx, %{}))
      assert state(view)["context"] == original["context"]
      assert state(view)["sources"] == original["sources"]
      assert state(view)["error"] == "proposal_in_progress"
    end

    act(view, ctx, "close")
    refute state(view)["open"]
  end

  test "acceptance and a pending revision retain the previous agreement and its history", ctx do
    view = open_board(ctx, ctx.facilitator)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "create", proposal(view, ctx))
    act(view, ctx, "accept", selected_request(view))
    accepted = state(view)["selected"]
    assert accepted["status"] == "accepted"
    assert accepted["accepted"]["operation"] == "accept"

    act(view, ctx, "begin_revision", selected_request(view))
    assert state(view)["mode"] == "revise"
    attrs = Map.merge(proposal(view, ctx), selected_request(view))
    act(view, ctx, "revise", Map.put(attrs, :conclusion, "Let the player leave a final note."))
    revised = state(view)["selected"]
    assert revised["status"] == "proposed"
    assert revised["proposal"]["conclusion"] == "Let the player leave a final note."
    assert revised["accepted"]["conclusion"] == accepted["accepted"]["conclusion"]
    assert revised["accepted"]["revision"] == accepted["accepted"]["revision"]

    act(view, ctx, "accept", selected_request(view))
    assert state(view)["selected"]["status"] == "accepted"
    act(view, ctx, "history", %{decision_id: revised["id"]})
    assert Enum.map(state(view)["history"], & &1["operation"]) == ["accept", "revise", "accept", "propose"]
    assert Enum.at(state(view)["history"], 2)["text"] == accepted["accepted"]["conclusion"]
  end

  test "revising a changed source keeps its discussed base until explicitly refreshed", ctx do
    view = open_board(ctx, ctx.facilitator)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "create", proposal(view, ctx))
    original = hd(state(view)["selected"]["proposal"]["sources"])

    assert {:ok, edited} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.idea.id,
               ctx.idea.revision,
               edit_attrs(%{body: "<p>The player can leave.</p>"})
             )

    publish_idea(ctx, edited)

    act(view, ctx, "reload")
    act(view, ctx, "begin_revision", selected_request(view))
    assert [%{"changed" => true, "preview" => "The player chooses to stay."}] = state(view)["sources"]
    act(view, ctx, "revise", Map.merge(proposal(view, ctx), selected_request(view)))
    assert hd(state(view)["selected"]["proposal"]["sources"])["version"] == original["version"]

    act(view, ctx, "begin_revision", selected_request(view))
    act(view, ctx, "refresh_sources")
    assert [%{"changed" => false, "preview" => "The player can leave."}] = state(view)["sources"]
    assert hd(state(view)["sources"])["version"] > original["version"]
  end

  test "private and foreign ideas never enter the proposal or source picker", ctx do
    private = idea_fixture(ctx, %{title: "Secret ending", body: "<p>Author only</p>"})
    other = ideation_fixture()
    foreign = idea_fixture(other, %{visibility: :shared, title: "Foreign ending"})
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new")
    act(view, ctx, "search_sources", %{type: "idea", search: "ending"})
    assert Enum.map(state(view)["sourceResults"], & &1["id"]) == [ctx.idea.id]

    for idea <- [private, foreign] do
      act(view, ctx, "preview_sources", %{sources: [%{type: "idea", id: idea.id}]})
      assert state(view)["sources"] == []
      assert state(view)["error"]
    end
  end

  test "a new proposal requires explicit refresh when undo restores a newer published source", ctx do
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    original = state(view)
    deleted = delete_source(ctx, ctx.idea)
    act(view, ctx, "reload")
    assert [%{"available" => false, "title" => "", "preview" => ""}] = state(view)["sources"]

    restored = restore_source(ctx, deleted)
    act(view, ctx, "reload")

    assert [%{"available" => false, "changed" => true, "preview" => "", "currentVersion" => current}] =
             state(view)["sources"]

    assert current == restored.revision
    assert hd(state(view)["sources"])["version"] == hd(original["sources"])["version"]
    act(view, ctx, "refresh_sources")

    assert [%{"available" => true, "changed" => false, "preview" => "The player chooses to stay."}] =
             state(view)["sources"]

    assert state(view)["context"] == original["context"]
    assert hd(state(view)["sources"])["version"] == restored.revision
    edited = edit_source(ctx, restored, "<p>Unpublished alternative</p>")
    act(view, ctx, "reload")
    assert hd(state(view)["sources"])["preview"] == "The player chooses to stay."
    deleted = delete_source(ctx, edited)
    act(view, ctx, "reload")
    refute hd(state(view)["sources"])["available"]
    restored_again = restore_source(ctx, deleted)
    act(view, ctx, "reload")

    assert [%{"available" => false, "changed" => true, "preview" => "", "currentVersion" => current}] =
             state(view)["sources"]

    assert current == restored_again.revision
    assert hd(state(view)["sources"])["version"] == restored.revision
    act(view, ctx, "refresh_sources")
    assert [%{"available" => true, "changed" => false, "preview" => "Unpublished alternative"}] = state(view)["sources"]
    assert hd(state(view)["sources"])["version"] == current
    assert state(view)["context"] == original["context"]
  end

  test "a revision rehydrates its persisted source pin without exposing newer private or shared text", ctx do
    view = open_board(ctx, ctx.facilitator)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "create", proposal(view, ctx))
    original = hd(state(view)["selected"]["proposal"]["sources"])
    shared = ctx |> edit_source(ctx.idea, "<p>A newer shared ending</p>") |> then(&publish_idea(ctx, &1))
    private = edit_source(ctx, shared, "<p>A newer private ending</p>")
    deleted = delete_source(ctx, private)
    act(view, ctx, "reload")
    act(view, ctx, "begin_revision", selected_request(view))
    assert [%{"available" => false, "id" => nil, "preview" => ""}] = state(view)["sources"]
    context = state(view)["context"]

    restored = restore_source(ctx, deleted)
    edit_source(ctx, restored, "<p>Still author-only after undo</p>")
    act(view, ctx, "reload")

    assert [%{"available" => true, "changed" => true, "preview" => "The player chooses to stay."}] =
             state(view)["sources"]

    source = hd(state(view)["sources"])
    assert source["version"] == original["version"]
    assert source["currentVersion"] == restored.revision
    assert source["id"] == ctx.idea.id
    assert state(view)["context"] == context
    act(view, ctx, "revise", Map.merge(proposal(view, ctx), selected_request(view)))
    assert hd(state(view)["selected"]["proposal"]["sources"])["version"] == original["version"]
    assert hd(state(view)["selected"]["proposal"]["sources"])["preview"] == original["preview"]
  end

  test "a viewer can read but cannot create, accept, or reassign a decision", ctx do
    author = open_board(ctx, ctx.author)
    act(author, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(author, ctx, "create", proposal(author, ctx))
    selected = state(author)["selected"]

    viewer = open_board(ctx, ctx.viewer)
    act(viewer, ctx, "open")
    act(viewer, ctx, "select", %{decision_id: selected["id"]})
    refute state(viewer)["canPropose"]
    refute state(viewer)["selected"]["canAccept"]
    refute state(viewer)["selected"]["canRevise"]
    act(viewer, ctx, "accept", selected_request(viewer))
    assert state(viewer)["error"] == "unauthorized"

    act(author, ctx, "begin_revision", selected_request(author))
    attrs = author |> proposal(ctx) |> Map.merge(selected_request(author)) |> Map.put(:owner_id, ctx.author.user.id)
    act(author, ctx, "revise", attrs)
    assert state(author)["error"]
    assert state(author)["selected"]["proposal"]["responsibleId"] == ctx.facilitator.user.id
  end

  test "privacy and access transitions clear every decision preview and old events are fenced", ctx do
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "create", proposal(view, ctx))
    act(view, ctx, "history", %{decision_id: state(view)["selected"]["id"]})
    old = payload(view, ctx, %{})

    assert [%{"proposal" => %{"sources" => [%{"available" => true}]}}] = board(view)["decisions"]
    assert Jason.encode!(board(view)["decisions"]) =~ "The player chooses to stay."

    set_private_mode(ctx, true)
    await_privacy(view, true)
    act(view, ctx, "reload")
    refute state(view)["open"]
    assert state(view)["selected"] == nil
    assert state(view)["history"] == []
    assert state(view)["sources"] == []
    # The lane reads like the panel: nothing of a private source reaches the board.
    refute Jason.encode!(board(view)["decisions"]) =~ "The player chooses to stay."

    render_hook(
      view,
      "decisions_accept",
      Map.merge(old, %{decision_id: 1, revision: 1, request_key: Ecto.UUID.generate()})
    )

    assert state(view)["error"] == "stale_board"

    set_private_mode(ctx, false)
    await_privacy(view, false)
    act(view, ctx, "open")
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    render(view)
    # The dock injector stays mounted so it can come back; it just has no session.
    assert LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props["session-id"] == nil
    decisions = :sys.get_state(view.pid).socket.assigns.decisions
    refute decisions.open
    assert decisions.items == []
    assert :sys.get_state(view.pid).socket.assigns.canvas_decisions == []
  end

  test "the whole list is read at once and in the reader's order", ctx do
    {:ok, sources} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: ctx.idea.id}])

    decisions =
      for number <- 1..21 do
        assert {:ok, decision} =
                 Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, %{
                   title: "Proposal #{number}",
                   conclusion: "A shared alternative",
                   verb: "test",
                   responsible_id: ctx.facilitator.user.id,
                   sources: sources,
                   request_key: Ecto.UUID.generate()
                 })

        decision
      end

    view = open_board(ctx, ctx.viewer)
    act(view, ctx, "open")
    assert Enum.map(state(view)["items"], & &1["id"]) == decisions |> Enum.reverse() |> Enum.map(& &1.id)
    assert state(view)["viewerId"] == ctx.viewer.user.id
  end

  test "a responsible proposer registers in one step, declares application and withdraws a revision", ctx do
    sheet = Storyarn.SheetsFixtures.sheet_fixture(ctx.project, %{name: "Mara"})
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "search_targets", %{search: "Mar"})
    assert [%{"type" => "sheet", "id" => sheet_id, "name" => "Mara"}] = state(view)["targetResults"]
    assert sheet_id == sheet.id

    attrs =
      view
      |> proposal(ctx)
      |> Map.merge(%{owner_id: ctx.author.user.id, register: true, targets: [%{type: "sheet", id: sheet.id}]})

    act(view, ctx, "create", attrs)
    registered = state(view)["selected"]
    assert registered["status"] == "accepted"
    assert [%{"key" => key, "name" => "Mara", "application" => nil}] = registered["application"]["targets"]

    act(view, ctx, "declare", %{
      decision_id: registered["id"],
      agreement: registered["accepted"]["revision"],
      target_key: key,
      state: "applied",
      note: "Rewrote her motivation",
      request_key: Ecto.UUID.generate()
    })

    assert %{"pending" => 0, "targets" => [%{"application" => %{"state" => "applied"}}]} =
             state(view)["selected"]["application"]

    act(view, ctx, "history", %{decision_id: registered["id"]})
    assert [%{"kind" => "application", "targetName" => "Mara"}, %{"operation" => "registered"}] = state(view)["history"]

    act(view, ctx, "begin_revision", selected_request(view))
    act(view, ctx, "revise", Map.merge(attrs, Map.put(selected_request(view), :register, false)))
    assert state(view)["selected"]["status"] == "proposed"
    act(view, ctx, "withdraw", selected_request(view))
    assert state(view)["selected"]["status"] == "accepted"
    assert state(view)["selected"]["accepted"]["revision"] == registered["accepted"]["revision"]
  end

  test "selecting notes while a proposal is open adds them to its sources", ctx do
    other = idea_fixture(ctx, %{title: "Another ending", body: "<p>Leave at dawn.</p>", visibility: :shared})
    view = open_board(ctx, ctx.author)
    render_hook(view, "decisions_add_sources", payload(view, ctx, %{idea_ids: [other.id]}))
    assert state(view)["error"] == "stale_board"
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    assert LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["decision-draft"]

    render_hook(
      view,
      "decisions_add_sources",
      Map.delete(payload(view, ctx, %{idea_ids: [other.id]}), :decision_context)
    )

    assert Enum.map(state(view)["sources"], & &1["id"]) == [ctx.idea.id, other.id]
  end

  test "the board draws every decision and a lane card opens it with its discussion", ctx do
    view = open_board(ctx, ctx.author)
    act(view, ctx, "new", %{idea_ids: [ctx.idea.id]})
    act(view, ctx, "create", proposal(view, ctx))
    decision_id = state(view)["selected"]["id"]
    act(view, ctx, "close")

    assert [%{"id" => ^decision_id}] = board(view)["decisions"]
    assert board(view)["decision-focus"] == nil
    assert panels(view)["discussion"]["state"] == nil

    render_hook(view, "decisions_open", payload(view, ctx, %{decision_id: decision_id}))
    assert state(view)["mode"] == "detail"
    assert board(view)["decision-focus"] == decision_id
    discussion = panels(view)["discussion"]["state"]
    assert discussion["decisionId"] == decision_id
    assert discussion["presentation"] == "workspace"
    assert discussion["thread"] == nil

    render_hook(
      view,
      "comments_create",
      discussion_payload(view, ctx, %{body: "Does this hold?", client_request_id: Ecto.UUID.generate()})
    )

    thread = panels(view)["discussion"]["state"]["thread"]
    assert thread["source"]["type"] == "ideation_decision"
    assert thread["source"]["id"] == decision_id
    assert panels(view)["discussion"]["counts"] == %{Integer.to_string(decision_id) => 1}
    assert board(view)["comments"]["pins"] == []

    act(view, ctx, "select", %{decision_id: decision_id})
    assert panels(view)["discussion"]["state"]["thread"]["id"] == thread["id"]

    act(view, ctx, "close")
    assert panels(view)["discussion"]["state"] == nil
    refute board(view)["comments"]["open"]
    assert panels(view)["discussion"]["counts"] == %{Integer.to_string(decision_id) => 1}
  end

  test "a link to a decision's discussion opens the panel on that decision", ctx do
    {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, direct_proposal(ctx))

    assert {:ok, detail} =
             Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, {:decision, decision.id}, %{
               body: "Worth a second look",
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: []
             })

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.peer.user), path(ctx) <> "?thread=#{detail.thread.id}")
    assert state(view)["open"]
    assert state(view)["selected"]["id"] == decision.id
    assert panels(view)["discussion"]["state"]["thread"]["id"] == detail.thread.id
    refute board(view)["comments"]["presentation"] == "canvas"
  end

  test "opening a canvas conversation hands comments back to the board and closes the panel", ctx do
    {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, direct_proposal(ctx))
    view = open_board(ctx, ctx.author)
    render_hook(view, "decisions_open", payload(view, ctx, %{decision_id: decision.id}))
    assert panels(view)["discussion"]["state"]["decisionId"] == decision.id

    render_hook(view, "comments_open", %{
      epoch: :sys.get_state(view.pid).socket.assigns.epoch,
      session_id: ctx.session.id,
      idea_id: ctx.idea.id
    })

    refute state(view)["open"]
    assert panels(view)["discussion"]["state"] == nil
    assert board(view)["comments"]["ideaId"] == ctx.idea.id
    assert board(view)["comments"]["presentation"] == "canvas"
  end

  test "the dashboard lists every decision and a link naming only a decision opens its session", ctx do
    {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, direct_proposal(ctx))
    base = "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming"
    {:ok, dashboard, _} = live(log_in_user(ctx.conn, ctx.peer.user), base)
    render_async(dashboard)

    assert [%{"id" => session_id, "decisions" => [%{"id" => id}]}] = board(dashboard)["board"]["decision_sessions"]
    assert {session_id, id} == {ctx.session.id, decision.id}

    conn = log_in_user(ctx.conn, ctx.peer.user)
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, "#{base}?decision=#{decision.id}")
    assert to == "#{base}/#{ctx.session.id}?decision=#{decision.id}"
    {:ok, view, _} = live(conn, to)
    assert state(view)["open"]
    assert state(view)["selected"]["id"] == decision.id

    {:ok, missing, _} = live(log_in_user(ctx.conn, ctx.peer.user), "#{base}?decision=#{decision.id + 1_000_000}")
    refute state(missing)["open"]
  end

  defp open_board(ctx, actor) do
    {:ok, view, _} = live(log_in_user(ctx.conn, actor.user), path(ctx))
    view
  end

  defp edit_source(ctx, idea, body) do
    assert {:ok, edited} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               idea.revision,
               edit_attrs(%{body: body})
             )

    edited
  end

  defp delete_source(ctx, idea) do
    assert {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, idea.revision)
    deleted
  end

  defp restore_source(ctx, deleted) do
    assert {:ok, restored} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               deleted.id,
               deleted.revision,
               deleted.deleted_at
             )

    restored
  end

  defp set_private_mode(ctx, private?) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert {:ok, _} =
             Storyarn.IdeationFixtures.set_private_mode(
               ctx.facilitator,
               ctx.project.id,
               current.id,
               current.revision,
               private?
             )
  end

  defp path(ctx),
    do: "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"

  defp state(view), do: panels(view)["decisions"]
  defp panels(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props
  defp board(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props

  defp discussion_payload(view, ctx, attrs) do
    Map.merge(attrs, %{
      epoch: :sys.get_state(view.pid).socket.assigns.epoch,
      session_id: ctx.session.id,
      comment_context: panels(view)["discussion"]["state"]["context"]
    })
  end

  defp direct_proposal(ctx) do
    {:ok, sources} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: ctx.idea.id}])

    %{
      title: "Keep the ending quiet",
      conclusion: "Let the player choose to stay.",
      verb: "change",
      targets: [],
      responsible_id: ctx.facilitator.user.id,
      sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
      request_key: Ecto.UUID.generate()
    }
  end

  # The board learns about the round's privacy through PubSub and refreshes shortly after.
  defp await_privacy(view, private?) do
    result =
      Enum.reduce_while(1..200, :timeout, fn _, _ ->
        render(view)
        rounds = :sys.get_state(view.pid).socket.assigns.board.rounds

        if Enum.any?(rounds, &(&1.private == private?)) do
          {:halt, :ok}
        else
          Process.sleep(10)
          {:cont, :timeout}
        end
      end)

    assert result == :ok
  end

  defp payload(view, ctx, attrs) do
    Map.merge(
      %{
        epoch: :sys.get_state(view.pid).socket.assigns.epoch,
        session_id: ctx.session.id,
        decision_context: state(view)["context"]
      },
      attrs
    )
  end

  defp act(view, ctx, action, attrs \\ %{}), do: render_hook(view, "decisions_" <> action, payload(view, ctx, attrs))

  defp proposal(view, ctx) do
    %{
      title: "Keep the ending quiet",
      conclusion: "Let the player choose to stay.",
      reason: "It resolves the character's promise.",
      verb: "change",
      targets: [],
      owner_id: ctx.facilitator.user.id,
      sources: state(view)["sources"],
      request_key: Ecto.UUID.generate()
    }
  end

  defp selected_request(view) do
    selected = state(view)["selected"]
    %{decision_id: selected["id"], revision: selected["version"], request_key: Ecto.UUID.generate()}
  end
end
