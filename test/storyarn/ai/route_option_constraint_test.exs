defmodule Storyarn.AI.RouteOptionConstraintTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.AI.Operation
  alias Storyarn.AI.RouteOption
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask
  alias StoryarnTest.Sheets.AI.ContextTask, as: SheetContextTask

  setup do
    original = Application.get_env(:storyarn, ContractTask, [])

    Application.put_env(:storyarn, ContractTask,
      context_adapter: SheetContextTask,
      context_policy: sheet_policy()
    )

    on_exit(fn -> Application.put_env(:storyarn, ContractTask, original) end)
  end

  test "managed route options require non-null price units at the database boundary" do
    definition = constraint_definition("ai_route_options_lane_price")
    assert definition =~ "price_units IS NOT NULL"
  end

  test "legacy SQL constraints still require persisted subjects for their current scope allowlist" do
    for constraint_name <- [
          "ai_route_options_context_complete",
          "ai_operations_context_complete"
        ] do
      definition = constraint_definition(constraint_name)

      assert definition =~ "dialogue"
      assert definition =~ "flow_neighborhood"
      assert definition =~ "sheet"
      assert definition =~ "COALESCE"
      assert definition =~ "context_subject IS NULL"
      assert definition =~ "context_subject IS NOT NULL"
    end
  end

  test "route option changesets enforce context subject persistence by scope" do
    assert route_option_changeset("sheet", context_subject()).valid?
    refute route_option_changeset("sheet", nil).valid?
    refute route_option_changeset(nil, nil).valid?
    refute route_option_changeset("unknown", context_subject()).valid?
    refute route_option_changeset("sheet", %{context_subject() | "kind" => "dialogue"}).valid?
    refute route_option_changeset("sheet", context_subject(), "undeclared_sheet_source").valid?

    assert Enum.any?(
             route_option_changeset("sheet", context_subject()).constraints,
             &(&1.constraint == "ai_route_options_context_complete")
           )
  end

  test "operation changesets enforce context subject persistence by scope" do
    assert operation_changeset("sheet", context_subject()).valid?
    refute operation_changeset("sheet", nil).valid?
    refute operation_changeset(nil, nil).valid?
    refute operation_changeset("unknown", context_subject()).valid?

    assert Enum.any?(
             operation_changeset("sheet", context_subject()).constraints,
             &(&1.constraint == "ai_operations_context_complete")
           )
  end

  defp constraint_definition(name) do
    assert %{rows: [[definition]]} =
             Repo.query!(
               """
               SELECT pg_get_constraintdef(oid)
               FROM pg_constraint
               WHERE conname = $1
               """,
               [name]
             )

    definition
  end

  defp route_option_changeset(scope, context_subject, source_type \\ nil) do
    attrs =
      Map.merge(route_option_attrs(), %{
        context_hash: String.duplicate("a", 64),
        context_manifest: context_manifest(scope, source_type),
        context_subject: context_subject
      })

    RouteOption.issue_changeset(%RouteOption{}, attrs)
  end

  defp operation_changeset(scope, context_subject) do
    attrs =
      Map.merge(operation_attrs(), %{
        context_hash: String.duplicate("a", 64),
        context_manifest: context_manifest(scope),
        context_subject: context_subject
      })

    Operation.create_changeset(%Operation{}, attrs)
  end

  defp route_option_attrs do
    %{
      token_hash: :crypto.strong_rand_bytes(32),
      user_id: 1,
      actor_id: 1,
      workspace_id: 1,
      project_id: 1,
      task_id: "contract.echo",
      task_contract_hash: "contract-v1",
      input_hash: "input-v1",
      lane: "managed",
      provider: "fake",
      model: "fake-v1",
      credential_ref: %{"kind" => "managed"},
      payer: "storyarn",
      assignment_source: "test",
      consent_basis: "workspace_policy",
      policy_version: 1,
      price_id: "context-test",
      price_version: 1,
      price_units: 1,
      provider_configuration: %{"region" => "test"},
      expires_at: DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  defp operation_attrs do
    %{
      user_id: 1,
      actor_id: 1,
      workspace_id: 1,
      workspace_id_snapshot: 1,
      project_id: 1,
      project_id_snapshot: 1,
      route_option_id: 1,
      task_id: "contract.echo",
      task_contract_hash: "contract-v1",
      capability: "suggestions",
      idempotency_key: "context-test",
      execution_status: "queued",
      settlement_status: "not_applicable",
      input_hash: "input-v1",
      input_schema_version: "input-v1",
      output_schema_version: "output-v1",
      prompt_version: "prompt-v1",
      context_version: "context-v1",
      result_type: "context-result-v1",
      result_destination: %{"type" => "panel", "id" => "context-test"},
      policy_decision: %{"allowed" => true},
      execution_route: %{"lane" => "managed"}
    }
  end

  defp context_manifest(scope, source_type \\ nil) do
    included = if is_binary(source_type), do: [%{"type" => source_type}], else: []
    %{"scope" => scope, "included" => included, "excluded" => []}
  end

  defp sheet_policy do
    %{
      scope: :sheet,
      max_depth: 0,
      max_fan_out: 10,
      max_entities: 20,
      max_bytes: 16_384,
      tokenizer: nil,
      fields: %{}
    }
  end

  defp context_subject do
    %{
      "kind" => "sheet",
      "workspace_id" => 1,
      "project_id" => 1,
      "subject_id" => 1,
      "response_id" => nil,
      "block_ids" => []
    }
  end
end
