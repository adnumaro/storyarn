defmodule Storyarn.AI.Context.SourceLocksConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.SourceLocks
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias StoryarnTest.AI.ContextTask

  @timeout 15_000

  test "locks stay bounded to included children while the root blocks insert phantoms" do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "ai-source-locks-#{Ecto.UUID.generate()}@example.com"
        })

      scope = user_scope_fixture(user)
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      included = block_fixture(sheet, %{value: %{"content" => "Included"}})
      not_included = block_fixture(sheet, %{value: %{"content" => "Not included"}})
      workspace_id = project.workspace_id
      user_id = user.id

      try do
        operation = operation!(scope, project, sheet, included)
        parent = self()
        barrier = make_ref()

        holder =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              Repo.transaction(fn ->
                :ok = SourceLocks.acquire(operation)
                send(parent, {barrier, :locks_held})

                receive do
                  {^barrier, :release} -> :released
                after
                  @timeout -> exit(:source_lock_release_timeout)
                end
              end)
            end)
          end)

        assert_receive {^barrier, :locks_held}, @timeout

        assert row_lock_available?("blocks", not_included.id)
        refute row_lock_available?("blocks", included.id)
        refute row_lock_available?("sheets", sheet.id)

        send(holder.pid, {barrier, :release})

        assert {:ok, :released} = Task.await(holder, @timeout)
      after
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))

        Repo.delete_all(from(user_row in User, where: user_row.id == ^user_id))
      end
    end)
  end

  defp operation!(scope, project, sheet, block) do
    {:ok, subject_ref} =
      SubjectRef.sheet(project.workspace_id, project.id, sheet.id, block_ids: [block.id])

    {:ok, task} =
      AITask.new(
        ContextTask,
        Map.put(ContextTask.definition(), :context_policy, %{
          scope: :sheet,
          max_depth: 0,
          max_fan_out: 10,
          max_entities: 20,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })
      )

    {:ok, package} = Context.build_context(scope, task, subject_ref)

    %Operation{
      project_id_snapshot: project.id,
      context_hash: package.hash,
      context_manifest: Package.provenance(package),
      context_subject: elem(SubjectRef.persisted_map(subject_ref), 1)
    }
  end

  defp row_lock_available?("blocks", id) do
    row_lock_available?(
      "SELECT id FROM blocks WHERE id = $1 FOR UPDATE NOWAIT",
      id
    )
  end

  defp row_lock_available?("sheets", id) do
    row_lock_available?(
      "SELECT id FROM sheets WHERE id = $1 FOR UPDATE NOWAIT",
      id
    )
  end

  defp row_lock_available?(query, id) do
    fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          Repo.transaction(fn ->
            Repo.query!(query, [id])
          end)

          true
        rescue
          error in Postgrex.Error ->
            error.postgres.code != :lock_not_available && reraise(error, __STACKTRACE__)
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)
  end
end
