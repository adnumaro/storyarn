defmodule Storyarn.Ideation.IdeaConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Reveal
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  setup do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()

      author =
        %User{} |> User.email_changeset(%{email: unique_user_email()}) |> User.confirm_changeset() |> Repo.insert!()

      project = project_fixture(owner)
      membership = membership_fixture(project, author)
      owner_scope = user_scope_fixture(owner)
      scope = user_scope_fixture(author)

      {:ok, session} =
        Ideation.create_session(owner_scope, project.id, %{
          title: "Concurrent ideas",
          configuration: %{publication_policy: :facilitator_assisted}
        })

      ctx = %{project: project, session: session, author: scope, owner: owner_scope, membership: membership}
      idea = idea_fixture(ctx, %{publication_consent: :facilitator_assisted})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(from p in Project, where: p.id == ^project.id)
          Repo.delete_all(from w in Workspace, where: w.id == ^project.workspace_id)
          Repo.delete_all(from u in User, where: u.id in ^[owner.id, author.id])
        end)
      end)

      {:ok, Map.put(ctx, :idea, idea)}
    end)
  end

  test "competing autosaves keep one head and persist the losing input once", ctx do
    requests = Enum.map(["First contender", "Second contender"], &edit_attrs(%{body: &1}))

    results =
      race(
        Enum.map(requests, fn attrs ->
          fn ->
            Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id, 1, attrs)
          end
        end)
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:edit_conflict, _}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      {:ok, current} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id)
      {:ok, [conflict]} = Ideation.list_idea_conflicts(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id)
      assert Enum.sort([current.body, conflict.attempted.body]) == ["First contender", "Second contender"]
      assert current.revision == 2
      assert Repo.aggregate(from(r in Revision, where: r.idea_id == ^ctx.idea.id), :count) == 2
      assert Repo.aggregate(from(e in Edit, where: e.idea_id == ^ctx.idea.id), :count) == 3
      losing_request = Enum.find(requests, &(&1.request_key == conflict.request_key))

      assert {:error, {:edit_conflict, ^conflict}} =
               Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id, 1, losing_request)
    end)
  end

  test "simultaneous prepare retries share one durable frozen manifest", ctx do
    key = Ecto.UUID.generate()
    prepare = fn -> Ideation.prepare_idea_reveal(ctx.owner, ctx.project.id, ctx.session.id, key) end
    [{:ok, first}, {:ok, second}] = race([prepare, prepare])
    assert first == second
    assert first.manifest == [%{"idea_id" => ctx.idea.id, "revision" => 1}]

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(r in Reveal, where: r.session_id == ^ctx.session.id), :count) == 1
    end)
  end

  test "simultaneous reveal retries publish once and signal only after rows are readable", ctx do
    operation =
      Sandbox.unboxed_run(Repo, fn ->
        assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
        {:ok, operation} = Ideation.prepare_idea_reveal(ctx.owner, ctx.project.id, ctx.session.id, Ecto.UUID.generate())
        operation
      end)

    execute = fn -> Ideation.reveal_ideas(ctx.owner, ctx.project.id, ctx.session.id, operation.id) end
    [{:ok, first}, {:ok, second}] = race([execute, execute])
    assert first == second
    session_id = ctx.session.id
    assert_receive {:ideation_changed, ^session_id}, @timeout

    Sandbox.unboxed_run(Repo, fn ->
      assert {:ok, %{published_revision: 1}} = Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, ctx.idea.id)
      assert Repo.aggregate(from(p in Publication, where: p.idea_id == ^ctx.idea.id), :count) == 1
    end)

    refute_receive {:ideation_changed, _}
  end

  test "an edit waiting behind a role downgrade reauthorizes before saving", ctx do
    parent = self()

    downgrade =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transact(fn ->
            result = Projects.update_member_role(ctx.owner, ctx.project.id, ctx.membership.id, "viewer")
            send(parent, :downgrade_locked)

            receive do
              :commit -> result
            after
              @timeout -> {:error, :timeout}
            end
          end)
        end)
      end)

    try do
      assert_receive :downgrade_locked, @timeout

      editor =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            [[pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:editor_ready, pid})

            Ideation.update_idea(
              ctx.author,
              ctx.project.id,
              ctx.session.id,
              ctx.idea.id,
              1,
              edit_attrs(%{body: "Old permission"})
            )
          end)
        end)

      try do
        assert_receive {:editor_ready, pid}, @timeout
        Sandbox.unboxed_run(Repo, fn -> assert_waiting_on_lock(pid, 200) end)
        send(downgrade.pid, :commit)
        assert {:ok, _} = Task.await(downgrade, @timeout)
        assert {:error, :unauthorized} = Task.await(editor, @timeout)

        Sandbox.unboxed_run(Repo, fn ->
          assert {:ok, %{revision: 1, body: "<p>Original idea</p>"}} =
                   Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.idea.id)

          assert Repo.aggregate(from(e in Edit, where: e.idea_id == ^ctx.idea.id), :count) == 1
        end)
      after
        Task.shutdown(editor, :brutal_kill)
      end
    after
      Task.shutdown(downgrade, :brutal_kill)
    end
  end

  test "publication racing an edit never exposes the new unapproved revision", ctx do
    operation =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, operation} = Ideation.prepare_idea_reveal(ctx.owner, ctx.project.id, ctx.session.id, Ecto.UUID.generate())
        operation
      end)

    [publication, {:ok, updated}] =
      race([
        fn -> Ideation.reveal_ideas(ctx.owner, ctx.project.id, ctx.session.id, operation.id) end,
        fn ->
          Ideation.update_idea(
            ctx.author,
            ctx.project.id,
            ctx.session.id,
            ctx.idea.id,
            1,
            edit_attrs(%{body: "Private new revision"})
          )
        end
      ])

    assert updated.revision == 2

    Sandbox.unboxed_run(Repo, fn ->
      case publication do
        {:ok, _} ->
          assert {:ok, %{body: "<p>Original idea</p>", revision: 1}} =
                   Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, ctx.idea.id)

        {:error, :stale_reveal} ->
          assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, ctx.idea.id)
      end

      assert Repo.aggregate(from(r in Revision, where: r.idea_id == ^ctx.idea.id), :count) == 2
    end)
  end

  defp race(callbacks) do
    parent = self()

    tasks = Enum.map(callbacks, &start_contender(parent, &1))

    try do
      for _ <- tasks, do: assert_receive({:ready, _}, @timeout)
      Enum.each(tasks, &send(&1.pid, :run))
      Task.await_many(tasks, @timeout)
    after
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp start_contender(parent, callback) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> contend(parent, callback) end) end)
  end

  defp contend(parent, callback) do
    send(parent, {:ready, self()})

    receive do
      :run -> callback.()
    after
      @timeout -> flunk("contender was not released")
    end
  end

  defp assert_waiting_on_lock(_pid, 0), do: flunk("editor did not wait for the permission lock")

  defp assert_waiting_on_lock(pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [pid]).rows == [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_waiting_on_lock(pid, attempts - 1)
    end
  end
end
