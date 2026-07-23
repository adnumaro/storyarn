defmodule Storyarn.AI.ContextExecutionTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Executor
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Result
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias StoryarnTest.AI.ContractTask

  setup do
    original_config = Application.get_env(:storyarn, ContractTask, [])
    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})
    sheet = sheet_fixture(project)
    block = block_fixture(sheet, %{value: %{"content" => "initial context"}})

    FunWithFlags.enable(:ai_integrations, for_actor: user)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])
    configure_task(:background)

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_config)
      FunWithFlags.disable(:ai_integrations, for_actor: user)
    end)

    %{
      user: user,
      scope: scope,
      workspace: workspace,
      project: project,
      sheet: sheet,
      block: block
    }
  end

  test "context construction failure creates no route, operation, usage, or provider attempt", ctx do
    configure_task(:background, max_bytes: 180)

    oversized =
      ctx.block
      |> Block.update_changeset(%{value: %{"content" => String.duplicate("á", 200)}})
      |> Repo.update!()

    assert {:error, :context_too_large} =
             ctx
             |> intent!(oversized)
             |> AI.preflight()

    assert Repo.aggregate(RouteOption, :count) == 0
    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(UsageEvent, :count) == 0
  end

  test "a route is bound to the exact preflight context hash", ctx do
    base = intent!(ctx, ctx.block)
    assert {:ok, preflight} = AI.preflight(base)
    assert preflight.context_disclosure.included_count == 2
    assert preflight.context_disclosure.truncated == false
    assert [%{requested_route_ref: route_ref}] = preflight.route_options

    update_block!(ctx.block, "changed after preflight")

    assert {:error, :stale_context} =
             ctx
             |> execution_intent!(ctx.block, route_ref)
             |> AI.execute()

    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(UsageEvent, :count) == 0
  end

  test "a queued operation is rechecked immediately before any provider attempt", ctx do
    base = intent!(ctx, ctx.block)
    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(base)
    assert {:ok, queued} = ctx |> execution_intent!(ctx.block, route_ref) |> AI.execute()
    assert queued.execution_status == "queued"
    assert is_binary(queued.context_hash)
    refute inspect(queued.context_manifest) =~ "initial context"

    result = Repo.get_by!(Result, operation_id: queued.id)
    assert result.context_hash == queued.context_hash
    assert result.context_manifest == queued.context_manifest

    update_block!(ctx.block, "changed before worker claim")

    assert :ok = Executor.run(queued.id)
    cancelled = Repo.get!(Operation, queued.id)
    assert cancelled.execution_status == "cancelled"
    assert cancelled.error_classification == "stale_context"
    assert Repo.aggregate(UsageEvent, :count) == 0
    refute Repo.get_by(Result, operation_id: queued.id)
  end

  test "apply rejects stale context before invoking the feature mutation", ctx do
    configure_task(:inline)
    base = intent!(ctx, ctx.block)
    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(base)
    assert {:ok, operation} = ctx |> execution_intent!(ctx.block, route_ref) |> AI.execute()
    assert operation.execution_status == "succeeded"
    assert Repo.aggregate(UsageEvent, :count) == 1

    update_block!(ctx.block, "changed before apply")
    parent = self()

    assert {:error, :stale_context} =
             AI.apply_result(ctx.scope, operation.id, nil, fn _output, _provenance ->
               send(parent, :apply_called)
               {:ok, :applied}
             end)

    refute_received :apply_called
  end

  defp configure_task(execution_mode, overrides \\ []) do
    policy = %{
      scope: :sheet,
      max_depth: 0,
      max_fan_out: 10,
      max_entities: 20,
      max_bytes: Keyword.get(overrides, :max_bytes, 16_384),
      tokenizer: nil,
      fields: %{}
    }

    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: execution_mode,
      context_version: "sheet-context-v1",
      context_policy: policy
    )
  end

  defp intent!(ctx, block) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: input(ctx.sheet.id, block.id)
             })

    intent
  end

  defp execution_intent!(ctx, block, route_ref) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: input(ctx.sheet.id, block.id),
               requested_route_ref: route_ref,
               idempotency_key: "context-#{System.unique_integer([:positive])}"
             })

    intent
  end

  defp input(sheet_id, block_id) do
    %{
      "text" => "Use the selected context",
      "context_kind" => "sheet",
      "sheet_id" => sheet_id,
      "block_ids" => [block_id]
    }
  end

  defp update_block!(block, content) do
    block
    |> Block.update_changeset(%{value: %{"content" => content}})
    |> Repo.update!()
  end
end
