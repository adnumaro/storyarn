defmodule Storyarn.Ideation.BoardEventsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation

  setup do
    ideation_fixture()
  end

  test "session writes notify subscribers after the command commits, never on rollback", ctx do
    assert :ok = Ideation.subscribe_sessions(ctx.peer, ctx.project.id)
    project_id = ctx.project.id
    assert {:ok, _} = Ideation.create_session(ctx.author, project_id, %{title: "New direction"})
    assert_receive {:ideation_sessions_changed, ^project_id}
    assert {:error, _} = Ideation.create_session(ctx.author, project_id, %{title: ""})
    refute_receive {:ideation_sessions_changed, ^project_id}

    assert {:error, :rollback} =
             Repo.transact(fn ->
               {:ok, _} = Ideation.create_session(ctx.author, project_id, %{title: "Rolled back"})
               {:error, :rollback}
             end)

    refute_receive {:ideation_sessions_changed, ^project_id}
  end

  test "leaving a session unsubscribes both authorized idea topics", ctx do
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
    session_id = ctx.session.id
    idea_fixture(ctx)
    assert_receive {:ideation_changed, ^session_id}
    assert :ok = Ideation.unsubscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
    idea_fixture(ctx)
    idea_fixture(ctx, %{visibility: :shared})
    refute_receive {:ideation_changed, ^session_id}
  end
end
