defmodule Storyarn.Flows.AI.SourceLocksConcurrencyTest do
  use ExUnit.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.Flows.AI.ContextContract
  alias Storyarn.Flows.AI.SourceLocks
  alias Storyarn.Repo
  alias StoryarnTest.Flows.AI.ContextTask

  @timeout 15_000

  test "locks stay bounded to included nodes while the flow root blocks insert phantoms" do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "flows-ai-source-locks-#{Ecto.UUID.generate()}@example.com"
        })

      scope = user_scope_fixture(user)
      project = project_fixture(user)
      flow = flow_fixture(project)

      included =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Included"}
        })

      not_included =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Not included"}
        })

      workspace_id = project.workspace_id
      user_id = user.id

      try do
        operation = operation!(scope, project, included)
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

        assert row_lock_available?("flow_nodes", not_included.id)
        refute row_lock_available?("flow_nodes", included.id)
        refute row_lock_available?("flows", flow.id)

        send(holder.pid, {barrier, :release})

        assert {:ok, :released} = Task.await(holder, @timeout)
      after
        # Keep teardown schemaless so this Flow-owned test does not load foreign context schemas.
        Repo.query!("DELETE FROM workspaces WHERE id = $1", [workspace_id])
        Repo.query!("DELETE FROM users WHERE id = $1", [user_id])
      end
    end)
  end

  defp operation!(scope, project, node) do
    {:ok, subject_ref} =
      ContextContract.dialogue(project.workspace_id, project.id, node.id)

    {:ok, task} =
      AITask.new(
        ContextTask,
        Map.put(ContextTask.definition(), :context_policy, %{
          scope: :dialogue,
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

  defp row_lock_available?("flow_nodes", id) do
    row_lock_available?(
      "SELECT id FROM flow_nodes WHERE id = $1 FOR UPDATE NOWAIT",
      id
    )
  end

  defp row_lock_available?("flows", id) do
    row_lock_available?(
      "SELECT id FROM flows WHERE id = $1 FOR UPDATE NOWAIT",
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
