defmodule Storyarn.Ideation.SessionConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  setup do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      project = project_fixture(owner)
      editor = user_without_workspace()
      membership = membership_fixture(project, editor)
      scope = user_scope_fixture(editor)
      {:ok, session} = Ideation.create_session(scope, project.id, %{title: "Original"})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(from p in Project, where: p.id == ^project.id)
          Repo.delete_all(from w in Workspace, where: w.id == ^project.workspace_id)
          Repo.delete_all(from u in User, where: u.id in ^[owner.id, editor.id])
        end)
      end)

      {:ok,
       project: project, owner_scope: user_scope_fixture(owner), scope: scope, membership: membership, session: session}
    end)
  end

  test "competing edits commit exactly one head and one matching revision", ctx do
    Sandbox.unboxed_run(Repo, fn ->
      parent = self()

      tasks =
        for title <- ["First edit", "Second edit"] do
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:ready, self()})

              receive do
                :start -> Ideation.update_session(ctx.scope, ctx.project.id, ctx.session.id, 1, %{title: title})
              after
                @timeout -> flunk("edit was not released")
              end
            end)
          end)
        end

      try do
        for _task <- tasks, do: assert_receive({:ready, _pid}, @timeout)
        Enum.each(tasks, &send(&1.pid, :start))
        results = Task.await_many(tasks, @timeout)
        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 1
        assert {:ok, current} = Ideation.get_session(ctx.scope, ctx.project.id, ctx.session.id)
        assert {:ok, [latest, original]} = Ideation.list_session_revisions(ctx.scope, ctx.project.id, ctx.session.id)
        assert current.revision == 2
        assert latest.number == 2
        assert latest.snapshot["title"] == current.title
        assert original.snapshot["title"] == "Original"
      after
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
      end
    end)
  end

  test "an edit blocked behind a membership downgrade reauthorizes after it commits", ctx do
    Sandbox.unboxed_run(Repo, fn ->
      parent = self()

      downgrade =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transact(fn ->
              # Hold the internal writer's commit; the public facade publishes only after its own commit.
              result =
                Storyarn.Projects.Memberships.update_member_role(
                  ctx.owner_scope,
                  ctx.project.id,
                  ctx.membership.id,
                  "viewer"
                )

              send(parent, :downgrade_pending)

              receive do
                :commit -> result
              after
                @timeout -> {:error, :downgrade_timeout}
              end
            end)
          end)
        end)

      try do
        assert_receive :downgrade_pending, @timeout

        edit =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
              send(parent, {:editing, backend_pid})
              Ideation.update_session(ctx.scope, ctx.project.id, ctx.session.id, 1, %{title: "Old permission"})
            end)
          end)

        try do
          assert_receive {:editing, backend_pid}, @timeout
          assert_waiting_on_lock(backend_pid, 200)
          send(downgrade.pid, :commit)
          assert {:ok, _membership} = Task.await(downgrade, @timeout)
          assert {:error, :unauthorized} = Task.await(edit, @timeout)
          assert {:ok, current} = Ideation.get_session(ctx.scope, ctx.project.id, ctx.session.id)
          assert current.title == "Original"
          assert current.revision == 1
          assert {:ok, [_original]} = Ideation.list_session_revisions(ctx.scope, ctx.project.id, ctx.session.id)
        after
          Task.shutdown(edit, :brutal_kill)
        end
      after
        Task.shutdown(downgrade, :brutal_kill)
      end
    end)
  end

  test "recovery rejects a busy surviving author without waiting or orphaning their data", ctx do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, capsule} =
        Repo.transact(fn ->
          Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")
          Ideation.capture_recovery(ctx.project.id)
        end)

      parent = self()

      actor_lock =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.one!(from u in User, where: u.id == ^ctx.scope.user.id, lock: "FOR UPDATE")
              send(parent, :recovery_actor_locked)

              receive do
                :release -> :ok
              after
                @timeout -> flunk("actor lock was not released")
              end
            end)
          end)
        end)

      try do
        assert_receive :recovery_actor_locked, @timeout

        assert {:error, :ideation_recovery_actors_busy} =
                 Repo.transact(fn ->
                   {:ok, _, _} = Projects.authorize_locked(ctx.owner_scope, ctx.project.id, :edit_content)
                   Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")
                   Ideation.restore_recovery(ctx.project.id, capsule)
                 end)

        assert {:ok, session} = Ideation.get_session(ctx.scope, ctx.project.id, ctx.session.id)
        assert session.created_by_id == ctx.scope.user.id
        assert session.deleted_at == nil
        send(actor_lock.pid, :release)
        assert {:ok, :ok} = Task.await(actor_lock, @timeout)

        assert {:ok, _} =
                 Repo.transact(fn ->
                   Repo.one!(from p in Project, where: p.id == ^ctx.project.id, lock: "FOR UPDATE")
                   Ideation.restore_recovery(ctx.project.id, capsule)
                 end)
      after
        Task.shutdown(actor_lock, :brutal_kill)
      end
    end)
  end

  test "competing round starts commit one active round and one session revision", ctx do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, _} = Ideation.create_round(ctx.scope, ctx.project.id, ctx.session.id, 1, %{})
      {:ok, session} = Ideation.create_round(ctx.scope, ctx.project.id, ctx.session.id, 2, %{})
      {:ok, rounds} = Ideation.list_rounds(ctx.scope, ctx.project.id, ctx.session.id)
      parent = self()

      tasks =
        for round <- rounds do
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:round_ready, self()})

              receive do
                :start -> Ideation.start_round(ctx.scope, ctx.project.id, ctx.session.id, round.id, session.revision)
              after
                @timeout -> flunk("round start was not released")
              end
            end)
          end)
        end

      try do
        for _task <- tasks, do: assert_receive({:round_ready, _pid}, @timeout)
        Enum.each(tasks, &send(&1.pid, :start))
        results = Task.await_many(tasks, @timeout)
        assert Enum.count(results, &match?({:ok, _}, &1)) == 1
        assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 1
        assert {:ok, [_one]} = Ideation.list_rounds(ctx.scope, ctx.project.id, ctx.session.id, status: :active)
        assert {:ok, %{revision: 4}} = Ideation.get_session(ctx.scope, ctx.project.id, ctx.session.id)
      after
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
      end
    end)
  end

  test "a contribution waiting for a committed round close is saved against that round as late", ctx do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, _} = Ideation.create_round(ctx.scope, ctx.project.id, ctx.session.id, 1, %{})
      {:ok, [round]} = Ideation.list_rounds(ctx.scope, ctx.project.id, ctx.session.id)
      {:ok, _} = Ideation.start_round(ctx.scope, ctx.project.id, ctx.session.id, round.id, 2)
      parent = self()

      closer =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transact(fn ->
              {:ok, session} = Ideation.close_round(ctx.scope, ctx.project.id, ctx.session.id, round.id, 3)
              send(parent, :round_closed_uncommitted)

              receive do
                :commit -> {:ok, session}
              after
                @timeout -> flunk("round close was not committed")
              end
            end)
          end)
        end)

      try do
        assert_receive :round_closed_uncommitted, @timeout

        writer =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              [[pid]] = Repo.query!("SELECT pg_backend_pid()").rows
              send(parent, {:round_contribution_waiting, pid})

              Ideation.create_idea(ctx.scope, ctx.project.id, ctx.session.id, %{
                request_key: Ecto.UUID.generate(),
                configuration_version: 1,
                round_id: round.id,
                body: "Late arrival"
              })
            end)
          end)

        try do
          assert_receive {:round_contribution_waiting, pid}, @timeout
          assert_waiting_on_lock(pid, 200)
          send(closer.pid, :commit)
          assert {:ok, _} = Task.await(closer, @timeout)
          assert {:ok, idea} = Task.await(writer, @timeout)
          assert idea.round_id == round.id
          assert idea.late_contribution
        after
          Task.shutdown(writer, :brutal_kill)
        end
      after
        Task.shutdown(closer, :brutal_kill)
      end
    end)
  end

  defp assert_waiting_on_lock(_pid, 0), do: flunk("edit did not wait for the permission transaction")

  defp assert_waiting_on_lock(pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [pid]).rows == [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_waiting_on_lock(pid, attempts - 1)
    end
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end
end
