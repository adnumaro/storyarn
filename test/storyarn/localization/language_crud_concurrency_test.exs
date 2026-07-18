defmodule Storyarn.Localization.LanguageCrudConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000
  @blocked_timeout 5_000

  test "archiving a language waits for the shared localization inventory lock" do
    %{user: user, project: project, target: target} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "language-lock-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
        target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

        %{user: user, project: project, target: target}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from(language in ProjectLanguage,
            where: language.project_id == ^project.id
          )
        )

        Repo.delete_all(from(current in Project, where: current.id == ^project.id))
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(current in User, where: current.id == ^user.id))
      end)
    end)

    parent = self()

    lock_holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          Repo.transaction(fn ->
            :ok = LocalizableWords.lock_inventory!(project.id)
            send(parent, :inventory_locked)

            receive do
              :release_inventory -> :ok
            end
          end)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive :inventory_locked, 2_000

    archiver =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)
        send(parent, :archive_started)

        try do
          Localization.remove_language(target)
        after
          Sandbox.checkin(Repo)
        end
      end)

    assert_receive :archive_started, 2_000
    assert Task.yield(archiver, 150) == nil

    send(lock_holder.pid, :release_inventory)
    assert {:ok, _lock_result} = Task.await(lock_holder, 2_000)
    assert {:ok, archived} = Task.await(archiver, 2_000)
    assert archived.archived_at
  end

  test "inventory extraction locks the project before waiting for its advisory lock" do
    %{user: user, project: project} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "inventory-order-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
        _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

        %{user: user, project: project}
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    parent = self()
    barrier = make_ref()

    advisory_gate =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!(
              """
              SELECT pg_advisory_xact_lock(
                hashtextextended(concat($1::text, ':', $2::text), 0)
              )
              """,
              ["storyarn:localization:inventory", to_string(project.id)]
            )

            send(parent, {barrier, :advisory_locked})

            receive do
              {^barrier, :release_gate} -> :released
            after
              @timeout -> exit(:gate_release_timeout)
            end
          end)
        end)
      end)

    assert_receive {^barrier, :advisory_locked}, @timeout

    extractor =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :extractor_ready, backend_pid})
          LocalizableWords.extract_all(project.id)
        end)
      end)

    assert_receive {^barrier, :extractor_ready, backend_pid}, @timeout
    assert wait_until_blocked(backend_pid)
    assert project_row_locked?(project.id)

    send(advisory_gate.pid, {barrier, :release_gate})

    assert {:ok, _count} = Task.await(extractor, @timeout)
    assert {:ok, :released} = Task.await(advisory_gate, @timeout)
  end

  defp wait_until_blocked(backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked(backend_pid, deadline)
  end

  defp do_wait_until_blocked(backend_pid, deadline) do
    [[blocking_count]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          "SELECT cardinality(pg_blocking_pids($1))",
          [backend_pid]
        )
      end).rows

    cond do
      blocking_count > 0 ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked(backend_pid, deadline)
    end
  end

  defp project_row_locked?(project_id) do
    fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          Repo.transaction(fn ->
            Repo.query!(
              "SELECT id FROM projects WHERE id = $1 FOR UPDATE NOWAIT",
              [project_id]
            )
          end)

          false
        rescue
          error in Postgrex.Error ->
            error.postgres.code == :lock_not_available
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp cleanup_project(user, project) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(
        from(language in ProjectLanguage,
          where: language.project_id == ^project.id
        )
      )

      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
