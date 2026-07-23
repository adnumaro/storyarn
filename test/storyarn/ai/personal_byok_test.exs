defmodule Storyarn.AI.PersonalByokTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.CredentialResolver
  alias Storyarn.AI.CredentialResolver.Composite
  alias Storyarn.AI.CredentialResolver.Personal
  alias Storyarn.AI.Executor
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.InferenceProviders.Fake
  alias Storyarn.AI.InferenceProviders.Personal.OpenAI, as: PersonalOpenAI
  alias Storyarn.AI.Integration
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PersonalConsent
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.Result
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask

  @validation_stub StoryarnTest.AI.OpenAI
  @inference_stub StoryarnTest.AI.PersonalOpenAI

  setup do
    original_task = Application.get_env(:storyarn, ContractTask, [])
    original_resolver = Application.get_env(:storyarn, CredentialResolver)
    original_composite = Application.get_env(:storyarn, Composite, [])
    original_providers = Application.get_env(:storyarn, InferenceProviders, [])
    original_consents = Application.get_env(:storyarn, PersonalConsents, [])

    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :inline,
      allowed_lanes: [:personal_byok],
      personal_byok_allowed?: true,
      personal_cost_class: "standard",
      managed_price: nil
    )

    Application.put_env(:storyarn, CredentialResolver, Composite)
    Application.put_env(:storyarn, Composite, adapters: %{personal_byok: Personal})

    Application.put_env(:storyarn, InferenceProviders, providers: %{"fake" => Fake, "openai" => PersonalOpenAI})

    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["personal_byok"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_task)
      restore_env(CredentialResolver, original_resolver)
      Application.put_env(:storyarn, Composite, original_composite)
      Application.put_env(:storyarn, InferenceProviders, original_providers)
      Application.put_env(:storyarn, PersonalConsents, original_consents)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace, project: project}
  end

  test "personal preflight discloses connection and consent gates before issuing a route", ctx do
    intent = intent!(ctx, "draft")

    assert {:ok, %{route_options: [], personal_choices: [choice]}} = AI.preflight(intent)
    assert choice.provider == "openai"
    assert choice.status == :connect_required
    assert choice.payer == "personal_provider_account"
    assert choice.processing_location == "provider-controlled"
    assert choice.consent_policy_version == PersonalConsents.policy_text_version()
    refute Map.has_key?(choice, :route)

    integration = connect_openai!(ctx.owner)

    assert {:ok, %{route_options: [], personal_choices: [choice]}} = AI.preflight(intent)
    assert choice.status == :consent_required
    assert choice.integration_id == integration.id

    assert {:ok, %PersonalConsent{} = consent} =
             AI.grant_personal_consent(intent, integration.id, PersonalConsents.policy_text_version())

    assert consent.user_id == ctx.owner.id
    assert consent.workspace_id == ctx.workspace.id
    assert consent.integration_id == integration.id
    assert consent.capability == "suggestions"
    assert consent.cost_class == "standard"

    assert {:ok, %{route_options: [route], personal_choices: [ready]}} = AI.preflight(intent)
    assert ready.status == :ready
    assert route.lane == :personal_byok
    assert route.provider == "openai"
    assert route.model == "personal-deterministic-v1"
    assert route.payer == "personal_provider_account"
    assert is_nil(route.price_id)
    assert is_nil(route.price_version)
    assert is_nil(route.price_units)
  end

  test "workspace owner can use personal BYOK when member access is disabled", ctx do
    assert {:ok, _policy} = AI.update_workspace_policy(ctx.scope, ctx.workspace.id, [])

    assert {:ok, %{route_options: [], personal_choices: [choice]}} =
             ctx
             |> intent!("owner-only draft")
             |> AI.preflight()

    assert choice.provider == "openai"
    assert choice.status == :connect_required
  end

  test "workspace member needs the owner-controlled personal lane", ctx do
    editor = user_fixture()
    workspace_membership_fixture(ctx.workspace, editor, "admin")
    membership_fixture(ctx.project, editor, "editor")
    editor_scope = user_scope_fixture(editor)
    FunWithFlags.enable(:ai_integrations, for_actor: editor)
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: editor) end)

    assert {:ok, _policy} = AI.update_workspace_policy(ctx.scope, ctx.workspace.id, [])

    editor_ctx = %{ctx | owner: editor, scope: editor_scope}
    assert {:error, :ai_disabled} = editor_ctx |> intent!("blocked member") |> AI.preflight()

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["personal_byok"])

    assert {:ok, %{personal_choices: [choice]}} =
             editor_ctx
             |> intent!("allowed member")
             |> AI.preflight()

    assert choice.status == :connect_required
  end

  test "executes with only the actor key and never touches managed allowance", ctx do
    integration = connect_openai!(ctx.owner)
    intent = consented_intent!(ctx, integration, "private draft")
    stub_openai_success("private draft")

    route_ref = personal_route_ref!(intent)
    execute_intent = execution_intent!(ctx, "private draft", route_ref, "personal-success")

    assert {:ok, %Operation{} = operation} = AI.execute(execute_intent)
    assert operation.execution_status == "succeeded"
    assert operation.settlement_status == "not_applicable"
    assert operation.execution_route["lane"] == "personal_byok"
    assert operation.execution_route["payer"] == "personal_provider_account"

    usage = Repo.get_by!(UsageEvent, operation_id: operation.id)
    assert usage.status == "succeeded"
    assert usage.lane == "personal_byok"
    assert usage.provider == "openai"
    assert usage.input_units == 12
    assert usage.output_units == 7
    assert is_nil(usage.provider_cost)
    assert is_nil(usage.provider_cost_currency)

    assert Repo.aggregate(AllowanceReservation, :count) == 0
    assert Repo.aggregate(AllowanceLedgerEntry, :count) == 0
    assert Repo.get!(Integration, integration.id).last_used_at

    assert {:ok, %{"echo" => %{"text" => "private draft"}}, _operation} =
             AI.get_result(ctx.scope, operation.id)
  end

  test "another project member cannot see, consent to, or execute with the owner's key", ctx do
    integration = connect_openai!(ctx.owner)

    editor = user_fixture()
    membership_fixture(ctx.project, editor, "editor")
    editor_scope = user_scope_fixture(editor)
    FunWithFlags.enable(:ai_integrations, for_actor: editor)
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: editor) end)

    editor_ctx = %{ctx | owner: editor, scope: editor_scope}
    editor_intent = intent!(editor_ctx, "editor draft")

    assert {:ok, %{route_options: [], personal_choices: [choice]}} = AI.preflight(editor_intent)
    assert choice.status == :connect_required
    assert is_nil(choice.integration_id)

    assert {:error, :integration_unavailable} =
             AI.grant_personal_consent(
               editor_intent,
               integration.id,
               PersonalConsents.policy_text_version()
             )

    assert Repo.aggregate(PersonalConsent, :count) == 0
  end

  test "disconnecting a queued key cancels before provider access and requires fresh consent", ctx do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :background,
      allowed_lanes: [:personal_byok],
      personal_byok_allowed?: true,
      personal_cost_class: "standard",
      managed_price: nil
    )

    integration = connect_openai!(ctx.owner)
    intent = consented_intent!(ctx, integration, "queued draft")
    route_ref = personal_route_ref!(intent)
    execute_intent = execution_intent!(ctx, "queued draft", route_ref, "personal-queued")

    assert {:ok, %Operation{execution_status: "queued"} = queued} = AI.execute(execute_intent)
    assert {:ok, _revoked} = AI.revoke(ctx.owner, integration)
    assert :ok = Executor.run(queued.id)

    cancelled = Repo.get!(Operation, queued.id)
    assert cancelled.execution_status == "cancelled"
    assert cancelled.settlement_status == "not_applicable"
    refute Repo.get_by(UsageEvent, operation_id: queued.id)
    refute Repo.get_by(Result, operation_id: queued.id)
    assert Repo.get_by!(PersonalConsent, integration_id: integration.id).revoked_at

    replacement = connect_openai!(ctx.owner, "sk-proj-replacement-wxyz")

    assert {:ok, %{route_options: [], personal_choices: [choice]}} =
             ctx |> intent!("fresh consent") |> AI.preflight()

    assert choice.status == :consent_required
    assert choice.integration_id == replacement.id
  end

  test "a stale consent policy version invalidates an already-issued personal route", ctx do
    integration = connect_openai!(ctx.owner)
    intent = consented_intent!(ctx, integration, "version bound")
    route_ref = personal_route_ref!(intent)

    Application.put_env(:storyarn, PersonalConsents, policy_text_version: "personal-egress-test-v2")

    assert {:error, :route_ref_stale} =
             ctx
             |> execution_intent!("version bound", route_ref, "stale-consent-version")
             |> AI.execute()

    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(UsageEvent, :count) == 0
  end

  test "scheduled execution can never consent to or route through a personal credential", ctx do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :background,
      allowed_lanes: [:personal_byok],
      personal_byok_allowed?: true,
      personal_cost_class: "standard",
      managed_price: nil,
      scheduled_allowed?: true
    )

    integration = connect_openai!(ctx.owner)
    scheduled = intent!(ctx, "scheduled", scheduled?: true)

    assert {:error, :personal_byok_unattended} =
             AI.grant_personal_consent(
               scheduled,
               integration.id,
               PersonalConsents.policy_text_version()
             )

    assert {:error, :no_route} = AI.preflight(scheduled)
    assert Repo.aggregate(PersonalConsent, :count) == 0
  end

  test "personal provider errors never fall back to managed and only 401 revokes the key", ctx do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :inline,
      allowed_lanes: [:managed, :personal_byok],
      personal_byok_allowed?: true,
      personal_cost_class: "standard",
      managed_price: %{id: "contract-free", version: 1, units: 1}
    )

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["managed", "personal_byok"])

    integration = connect_openai!(ctx.owner)
    first_intent = consented_intent!(ctx, integration, "forbidden")
    first_route_ref = personal_route_ref!(first_intent)
    stub_openai_status(403)

    assert {:ok, first} =
             ctx
             |> execution_intent!("forbidden", first_route_ref, "personal-403")
             |> AI.execute()

    assert first.execution_status == "failed"
    assert first.error_classification == "provider_error"
    assert Repo.get_by!(UsageEvent, operation_id: first.id).lane == "personal_byok"
    refute Repo.get!(Integration, integration.id).revoked_at

    second_intent = intent!(ctx, "unauthorized")
    second_route_ref = personal_route_ref!(second_intent)
    stub_openai_status(401)

    assert {:ok, second} =
             ctx
             |> execution_intent!("unauthorized", second_route_ref, "personal-401")
             |> AI.execute()

    assert second.execution_status == "failed"
    assert second.error_classification == "unauthorized"
    assert Repo.get!(Integration, integration.id).revoked_at
    assert Repo.get_by!(PersonalConsent, integration_id: integration.id).revoked_at
    assert Repo.aggregate(UsageEvent, :count) == 2
    assert Repo.aggregate(AllowanceReservation, :count) == 0
  end

  test "revoking consent after delivery blocks applying the result", ctx do
    integration = connect_openai!(ctx.owner)
    intent = consented_intent!(ctx, integration, "do not apply")
    stub_openai_success("do not apply")
    route_ref = personal_route_ref!(intent)

    assert {:ok, %Operation{execution_status: "succeeded"} = operation} =
             ctx
             |> execution_intent!("do not apply", route_ref, "personal-apply")
             |> AI.execute()

    consent = Repo.get_by!(PersonalConsent, integration_id: integration.id)
    assert {:ok, _revoked} = AI.revoke_personal_consent(ctx.scope, consent.id)

    assert {:error, :consent_revoked} =
             AI.apply_result(ctx.scope, operation.id, nil, fn _output, _provenance ->
               flunk("revoked personal output must not reach the mutation callback")
             end)

    assert Repo.get_by(Result, operation_id: operation.id)
    assert is_nil(Repo.get!(Operation, operation.id).user_disposition)
  end

  defp connect_openai!(user, api_key \\ "sk-proj-personal-abcd") do
    Req.Test.stub(@validation_stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
    assert {:ok, integration} = AI.connect(user, :openai, api_key)
    integration
  end

  defp consented_intent!(ctx, integration, text) do
    intent = intent!(ctx, text)

    assert {:ok, %PersonalConsent{}} =
             AI.grant_personal_consent(
               intent,
               integration.id,
               PersonalConsents.policy_text_version()
             )

    intent
  end

  defp personal_route_ref!(intent) do
    assert {:ok, %{route_options: options}} = AI.preflight(intent)
    assert %{requested_route_ref: route_ref} = Enum.find(options, &(&1.lane == :personal_byok))
    route_ref
  end

  defp intent!(ctx, text, opts \\ []) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               scheduled?: Keyword.get(opts, :scheduled?, false)
             })

    intent
  end

  defp execution_intent!(ctx, text, route_ref, idempotency_key) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               requested_route_ref: route_ref,
               idempotency_key: idempotency_key
             })

    intent
  end

  defp stub_openai_success(expected_text) do
    Req.Test.stub(@inference_stub, fn conn ->
      assert conn.request_path == "/v1/chat/completions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk-proj-personal-abcd"]

      {:ok, encoded, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(encoded)
      assert body["model"] == "personal-deterministic-v1"
      assert body["store"] == false
      assert body["messages"] |> Enum.at(1) |> Map.fetch!("content") |> Jason.decode!() == %{"text" => expected_text}

      Req.Test.json(conn, %{
        "id" => "personal-openai-request",
        "choices" => [
          %{"message" => %{"content" => Jason.encode!(%{"echo" => %{"text" => expected_text}})}}
        ],
        "usage" => %{"prompt_tokens" => 12, "completion_tokens" => 7}
      })
    end)
  end

  defp stub_openai_status(status) do
    Req.Test.stub(@inference_stub, fn conn -> Plug.Conn.resp(conn, status, "{}") end)
  end

  defp restore_env(module, nil), do: Application.delete_env(:storyarn, module)
  defp restore_env(module, value), do: Application.put_env(:storyarn, module, value)
end
