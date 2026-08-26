defmodule Storyarn.Architecture.AIFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI

  @established_contract [
    adapter_for: 1,
    ai_command_id?: 1,
    allowance_summary: 2,
    apply_result: 4,
    assign_integration: 3,
    cancel: 2,
    connect: 3,
    created_operation?: 3,
    delete_personal_preference: 3,
    dismiss_result: 2,
    execute: 1,
    get_active: 2,
    get_operation: 2,
    get_operations_by_keys: 3,
    get_replayable_result: 3,
    get_result: 2,
    get_task: 1,
    get_workspace_policy: 2,
    grant_personal_consent: 3,
    integration_model_status: 1,
    list_active: 1,
    list_assignment_states: 2,
    managed_provenance: 0,
    model_catalog: 0,
    models_for_provider: 1,
    new_intent: 2,
    personal_preference_impacts: 2,
    personal_preferences: 2,
    personal_preferences_overview: 1,
    preflight: 1,
    provider_metadata: 0,
    put_personal_preference: 5,
    record_result_view: 2,
    registered_tasks: 0,
    release_if_unstarted: 2,
    replace_integration_key: 3,
    resolve_route: 1,
    revalidate_integration: 2,
    revoke: 2,
    revoke_personal_consent: 2,
    unassign_integration: 3,
    update_workspace_policy: 3,
    with_personal_integration: 3
  ]

  @technical_entrypoints [
    expire_results: 0,
    grant_allowance: 3,
    managed_diagnostic_probe: 0,
    purge_expired_route_options: 0,
    reconcile_reservations: 4,
    run_execution_job: 1,
    run_execution_job_with: 4
  ]

  test "the AI root facade preserves its established contract and explicit technical entrypoints" do
    assert exports(AI) == Enum.sort(@established_contract ++ @technical_entrypoints)
  end

  test "technical worker and operator entrypoints stay hidden from generated public docs" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(AI)

    hidden =
      for {{:function, name, arity}, _, _, :hidden, _} <- entries,
          {name, arity} in @technical_entrypoints,
          do: {name, arity}

    assert Enum.sort(hidden) == Enum.sort(@technical_entrypoints)
  end

  test "the root facade remains declarative delegation without business logic" do
    source = File.read!("lib/storyarn/ai.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert length(Regex.scan(~r/^\s*defdelegate\s/m, source)) == 50
  end

  defp exports(module) do
    :functions
    |> module.__info__()
    |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
    |> Enum.sort()
  end
end
