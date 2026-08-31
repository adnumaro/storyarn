defmodule StoryarnTest.Sheets.AI.ContextTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.Sheets.AI.ContextContract
  alias Storyarn.Sheets.AI.SheetContext
  alias Storyarn.Sheets.AI.SourceLocks

  @impl true
  def definition do
    %{
      id: "sheets.context.test",
      capability: :suggestions,
      data_scope: :entity,
      required_domain_permissions: %{execute: :view, apply: :edit_content},
      allowed_lanes: [:managed],
      input_schema_version: "sheets-context-input-v1",
      output_schema_version: "sheets-context-output-v1",
      prompt_version: "sheets-context-prompt-v1",
      context_version: "sheets-context-v1",
      context_policy: %{
        scope: :sheet,
        max_depth: 0,
        max_fan_out: 10,
        max_entities: 20,
        max_bytes: 16_384,
        tokenizer: nil,
        fields: %{}
      },
      max_input_bytes: 4_096,
      max_output_bytes: 4_096,
      execution_mode: :background,
      timeout_ms: 1_000,
      result_type: "sheets_context_test",
      result_destination: %{type: :panel, id: "sheets-context-test"},
      result_ttl_seconds: 300,
      personal_byok_allowed?: false,
      personal_cost_class: nil,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{id: "sheets-context-test", version: 1, units: 1},
      enabled?: true,
      command_ids: [],
      provider_options: %{}
    }
  end

  @impl true
  def authorize_subject(_scope, _intent_or_operation, _phase), do: :ok

  @impl true
  def post_operation_authorization_mode, do: :lock_free

  @impl true
  def context_contract(policy) do
    case Map.get(policy, :scope, Map.get(policy, "scope")) do
      :none -> nil
      _sheet_scope -> ContextContract
    end
  end

  def sheet_subject(workspace_id, project_id, sheet_id, opts \\ []),
    do: ContextContract.sheet(workspace_id, project_id, sheet_id, opts)

  @impl true
  def subject_current?(_operation), do: true

  @impl true
  def context_subject(%ExecutionIntent{} = intent) do
    case intent.input do
      %{"context_kind" => "sheet", "sheet_id" => sheet_id} = input ->
        ContextContract.sheet(
          Map.get(input, "context_workspace_id", intent.workspace_id),
          Map.get(input, "context_project_id", intent.project_id),
          sheet_id,
          block_ids: Map.get(input, "block_ids", [])
        )

      _input ->
        {:error, :invalid_context_subject}
    end
  end

  def context_subject(_operation), do: {:error, :invalid_context_subject}

  @impl true
  def build_context(project, %SubjectRef{kind: :sheet} = subject_ref, policy, entity_builder),
    do: SheetContext.build(project, subject_ref, policy, entity_builder)

  @impl true
  def acquire_source_locks(%Operation{context_subject: %{} = persisted} = operation) do
    case ContextContract.from_persisted_subject(persisted) do
      {:ok, %SubjectRef{kind: :sheet}} -> SourceLocks.acquire(operation)
      _invalid -> {:error, :stale_context}
    end
  end

  def acquire_source_locks(%Operation{}), do: {:error, :stale_context}
end
