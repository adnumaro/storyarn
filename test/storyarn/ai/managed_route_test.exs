defmodule Storyarn.AI.ManagedRouteTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.Operation
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.ProviderBudgetReservation
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Tasks.ManagedDiagnostic
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask

  setup do
    original_route = Application.get_env(:storyarn, RouteResolver)
    original_settlement = Application.get_env(:storyarn, Settlement)
    original_task = Application.get_env(:storyarn, ContractTask, [])
    Application.put_env(:storyarn, Settlement, Storyarn.AI.Settlement.Managed)
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :inline)

    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, RouteResolver, original_route)
      Application.put_env(:storyarn, Settlement, original_settlement)
      Application.put_env(:storyarn, ContractTask, original_task)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace, project: project, route: original_route[:managed]}
  end

  test "managed configuration and endpoint circuit breakers fail closed", ctx do
    for override <- [
          [enabled: false],
          [verified_zdr: false],
          [verified_no_training: false],
          [endpoint: "http://unverified.test/v1/chat/completions"],
          [endpoint: "https://user:secret@verified.test/v1/chat/completions"],
          [endpoint: "https://verified.test/v1/chat/completions?api_key=secret"],
          [endpoint: "https://verified.test/v1/chat/completions#secret"],
          [provider_price: Keyword.put(ctx.route[:provider_price], :input_per_million, %{})],
          [
            provider_price:
              ctx.route[:provider_price]
              |> Keyword.put(:input_per_million, "1")
              |> Keyword.put(:max_estimated_cost, "0")
          ]
        ] do
      configure_route(ctx.route, override)
      assert {:error, :no_route} = ctx |> preflight_intent("blocked-#{inspect(override)}") |> AI.preflight()
      assert AI.managed_provenance() == nil
    end

    assert Repo.aggregate(Operation, :count) == 0
  end

  test "the diagnostic contract rejects unrecognized input and output fields" do
    probe = ManagedDiagnostic.probe()

    assert :ok = ManagedDiagnostic.validate_input(%{"probe" => probe})

    assert {:error, :invalid_diagnostic_input} =
             ManagedDiagnostic.validate_input(%{"probe" => probe, "extra" => true})

    assert :ok = ManagedDiagnostic.validate_output(%{"status" => "ok"})

    assert {:error, :invalid_diagnostic_output} =
             ManagedDiagnostic.validate_output(%{"status" => "ok", "extra" => true})
  end

  test "provider endpoints stay in server configuration and are not persisted", ctx do
    assert {:ok, %{route_options: [_route]}} = ctx |> preflight_intent("no-endpoint-at-rest") |> AI.preflight()

    route_option = Repo.one!(RouteOption)
    refute Map.has_key?(route_option.provider_configuration, "endpoint")
    assert route_option.provider_configuration["data_retention"] == "zero_data_retention"
    assert route_option.provider_configuration["training_usage"] == "disabled"
  end

  test "global daily and monthly provider ceilings block before an external call", ctx do
    grant!(ctx, 5, "global-cap")

    for {field, reason} <- [
          {:global_daily, :provider_daily_budget_exhausted},
          {:global_monthly, :provider_monthly_budget_exhausted}
        ] do
      configure_costs(ctx.route, field, "0.50")
      assert {:error, ^reason} = execute(ctx, "global-#{field}", "global-#{field}")
    end

    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(ProviderBudgetReservation, :count) == 0
    assert Repo.aggregate(AllowanceLedgerEntry, :count) == 1
    assert Repo.aggregate(OperatorAlert, :count) == 2
  end

  test "workspace provider ceiling and paused allowance are independent blockers", ctx do
    grant!(ctx, 5, "workspace-cap")
    configure_costs(ctx.route, :workspace_daily, "0.50")

    assert {:error, :workspace_provider_budget_exhausted} =
             execute(ctx, "workspace-cap", "workspace-cap-operation")

    configure_route(ctx.route, [])
    assert {:ok, _account} = Allowance.set_status(ctx.workspace.id, "paused")
    assert {:error, :allowance_paused} = execute(ctx, "paused", "paused-operation")

    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(ProviderBudgetReservation, :count) == 0
  end

  defp configure_costs(route, cap_field, cap) do
    provider_price = Keyword.put(route[:provider_price], :max_estimated_cost, "1.00")
    budget = route[:budget] |> Keyword.put(:global_daily, "100") |> Keyword.put(:global_monthly, "100")
    budget = budget |> Keyword.put(:workspace_daily, "100") |> Keyword.put(cap_field, cap)
    configure_route(route, provider_price: provider_price, budget: budget)
  end

  defp configure_route(route, overrides) do
    Application.put_env(:storyarn, RouteResolver, managed: Keyword.merge(route, overrides))
  end

  defp grant!(ctx, units, key) do
    assert {:ok, grant} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: key,
               kind: "one_time",
               units: units
             })

    grant
  end

  defp execute(ctx, text, idempotency_key) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text}
             })

    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(intent)

    assert {:ok, execute_intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               requested_route_ref: route_ref,
               idempotency_key: idempotency_key
             })

    AI.execute(execute_intent)
  end

  defp preflight_intent(ctx, text) do
    {:ok, intent} =
      AI.new_intent(ctx.scope, %{
        workspace_id: ctx.workspace.id,
        project_id: ctx.project.id,
        task_id: "contract.echo",
        input: %{"text" => text}
      })

    intent
  end
end
