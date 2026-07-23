defmodule Storyarn.AI.ContextExecutionTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Executor
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.Result
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.UsageEvent
  alias Storyarn.RateLimiter
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias StoryarnTest.AI.ContractTask

  @validation_stub StoryarnTest.AI.OpenAI

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

  test "a task cannot select context outside the intent workspace and project", ctx do
    other_workspace = workspace_fixture(ctx.user)
    other_project = project_fixture(ctx.user, %{workspace: other_workspace})
    other_sheet = sheet_fixture(other_project)

    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{
                 "text" => "Cross-project context must be rejected",
                 "context_kind" => "sheet",
                 "context_workspace_id" => other_workspace.id,
                 "context_project_id" => other_project.id,
                 "sheet_id" => other_sheet.id,
                 "block_ids" => []
               }
             })

    assert {:error, :unauthorized_context} = AI.preflight(intent)
    assert Repo.aggregate(RouteOption, :count) == 0
  end

  test "durable context subjects must match operation workspace and project snapshots", ctx do
    other_workspace = workspace_fixture(ctx.user)
    other_project = project_fixture(ctx.user, %{workspace: other_workspace})
    other_sheet = sheet_fixture(other_project)
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))

    assert {:ok, subject_ref} =
             SubjectRef.sheet(other_workspace.id, other_project.id, other_sheet.id)

    assert {:ok, persisted_subject} = SubjectRef.persisted_map(subject_ref)

    operation = %Operation{
      workspace_id_snapshot: ctx.workspace.id,
      project_id_snapshot: ctx.project.id,
      context_hash: String.duplicate("0", 64),
      context_manifest: %{},
      context_subject: persisted_subject
    }

    assert {:error, :unauthorized_context} =
             Context.operation_current?(ctx.scope, task, operation)
  end

  test "preflight rate limiting runs before context construction", ctx do
    enable_rate_limiting()
    attach_context_probe()

    for _index <- 1..60 do
      assert :ok = RateLimiter.check_ai_preflight(ctx.user.id, "contract.echo")
    end

    assert {:error, :rate_limited} =
             ctx
             |> intent!(ctx.block)
             |> AI.preflight()

    refute_received :context_built
    assert Repo.aggregate(RouteOption, :count) == 0
  end

  test "accepted-operation rate limiting runs before rebuilding context", ctx do
    base = intent!(ctx, ctx.block)
    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(base)

    enable_rate_limiting()
    attach_context_probe()

    for _index <- 1..20 do
      assert :ok = RateLimiter.check_ai_execution(ctx.user.id, "contract.echo")
    end

    assert {:error, :rate_limited} =
             ctx
             |> execution_intent!(ctx.block, route_ref)
             |> AI.execute()

    refute_received :context_built
    assert Repo.aggregate(Operation, :count) == 0
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

  test "a route with unavailable context limits does not roll back valid route options", ctx do
    intent = configure_mixed_routes_with_invalid_personal!(ctx)

    assert {:ok, preflight} = AI.preflight(intent)

    assert [%{lane: :managed, provider: "fake"}] = preflight.route_options
    assert [%{status: :model_context_limits_unavailable}] = preflight.personal_choices
    assert Repo.aggregate(RouteOption, :count) == 1
    assert Repo.get_by!(RouteOption, lane: "managed").provider == "fake"
    refute Repo.get_by(RouteOption, lane: "personal_byok")
  end

  test "a blocked personal route exposes only a content-free model-limit status", ctx do
    intent = configure_mixed_routes_with_invalid_personal!(ctx)

    assert {:ok, %{personal_choices: [choice]}} = AI.preflight(intent)

    assert choice.status == :model_context_limits_unavailable
    refute Map.has_key?(choice, :route)
    refute Map.has_key?(choice, :reason)
    refute inspect(choice) =~ "initial context"
  end

  test "preflight fails with the model-limit reason when every route is blocked", ctx do
    configure_invalid_managed_route!()

    assert {:error, :model_context_limits_unavailable} =
             ctx
             |> intent!(ctx.block)
             |> AI.preflight()

    assert Repo.aggregate(RouteOption, :count) == 0
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
      allowed_lanes: Keyword.get(overrides, :allowed_lanes, [:managed]),
      personal_byok_allowed?: Keyword.get(overrides, :personal_byok_allowed?, false),
      personal_cost_class: Keyword.get(overrides, :personal_cost_class),
      context_version: "sheet-context-v1",
      context_policy: policy
    )
  end

  defp configure_mixed_routes_with_invalid_personal!(ctx) do
    configure_task(:background,
      allowed_lanes: [:managed, :personal_byok],
      personal_byok_allowed?: true,
      personal_cost_class: "standard"
    )

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, [
               "managed",
               "personal_byok"
             ])

    configure_personal_model_without_limits!()
    integration = connect_openai!(ctx.user)
    intent = intent!(ctx, ctx.block)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _consent} =
             AI.grant_personal_consent(
               intent,
               integration.id,
               PersonalConsents.policy_text_version()
             )

    intent
  end

  defp configure_personal_model_without_limits! do
    original = Application.get_env(:storyarn, ModelCatalog)
    on_exit(fn -> restore_env(ModelCatalog, original) end)

    Application.put_env(:storyarn, ModelCatalog,
      models: [
        %{
          provider: "openai",
          model: "personal-deterministic-v1",
          catalog_version: 1,
          capabilities: [:translation, :suggestions, :tasks],
          input_modalities: [:text],
          output_modalities: [:text],
          structured_output: :json_schema,
          api_family: :structured_text,
          implementation_status: :executable,
          release_stage: :stable,
          context_window: nil,
          max_output_tokens: nil,
          processing_locations: ["provider-controlled"],
          pricing_version: nil,
          deprecated: false
        }
      ]
    )
  end

  defp configure_invalid_managed_route! do
    original = Application.get_env(:storyarn, RouteResolver)
    on_exit(fn -> restore_env(RouteResolver, original) end)

    managed =
      original
      |> Keyword.fetch!(:managed)
      |> Keyword.put(:provider, "unsupported")
      |> Keyword.put(:model, "missing-context-contract")

    Application.put_env(:storyarn, RouteResolver, Keyword.put(original, :managed, managed))
  end

  defp connect_openai!(user) do
    Req.Test.stub(@validation_stub, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => "personal-deterministic-v1"}]})
    end)

    assert {:ok, integration} = AI.connect(user, :openai, "sk-proj-context-limits")
    integration
  end

  defp restore_env(module, nil), do: Application.delete_env(:storyarn, module)
  defp restore_env(module, value), do: Application.put_env(:storyarn, module, value)

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

  defp enable_rate_limiting do
    original = Application.get_env(:storyarn, RateLimiter, [])
    on_exit(fn -> Application.put_env(:storyarn, RateLimiter, original) end)
    Application.put_env(:storyarn, RateLimiter, enabled: true)
  end

  defp attach_context_probe do
    handler_id = "context-probe-#{System.unique_integer([:positive])}"
    caller = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:ai, :context, :build],
        fn _event, _measurements, _metadata, pid -> send(pid, :context_built) end,
        caller
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
