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
end
