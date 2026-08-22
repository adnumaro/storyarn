defmodule StoryarnTest.Flows.AI.ContextTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.Flows.AI.ContextContract
  alias Storyarn.Flows.AI.DialogueContext
  alias Storyarn.Flows.AI.FlowNeighborhoodContext
  alias Storyarn.Flows.AI.SourceLocks

  @impl true
  def definition do
    %{
      id: "flows.context.test",
      capability: :suggestions,
      data_scope: :entity,
      required_domain_permissions: %{execute: :view, apply: :edit_content},
      allowed_lanes: [:managed],
      input_schema_version: "flows-context-input-v1",
      output_schema_version: "flows-context-output-v1",
      prompt_version: "flows-context-prompt-v1",
      context_version: "flows-context-v1",
      context_policy: %{
        scope: :flow_neighborhood,
        max_depth: 1,
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
      result_type: "flows_context_test",
      result_destination: %{type: :panel, id: "flows-context-test"},
      result_ttl_seconds: 300,
      personal_byok_allowed?: false,
      personal_cost_class: nil,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{id: "flows-context-test", version: 1, units: 1},
      enabled?: true,
      command_ids: [],
      provider_options: %{}
    }
  end

  @impl true
  def authorize_subject(_scope, _intent_or_operation, _phase), do: :ok

  @impl true
  def context_contract(policy) do
    case Map.get(policy, :scope, Map.get(policy, "scope")) do
      :none -> nil
      _flow_scope -> ContextContract
    end
  end

  def flow_neighborhood_subject(workspace_id, project_id, node_id),
    do: ContextContract.flow_neighborhood(workspace_id, project_id, node_id)

  def dialogue_subject(workspace_id, project_id, node_id, opts \\ []),
    do: ContextContract.dialogue(workspace_id, project_id, node_id, opts)

  @impl true
  def subject_current?(_operation), do: true

  @impl true
  def context_subject(%ExecutionIntent{} = intent) do
    case intent.input do
      %{"context_kind" => "flow", "node_id" => node_id} ->
        ContextContract.flow_neighborhood(intent.workspace_id, intent.project_id, node_id)

      %{"context_kind" => "dialogue", "node_id" => node_id} = input ->
        ContextContract.dialogue(intent.workspace_id, intent.project_id, node_id,
          response_id: Map.get(input, "response_id")
        )

      _input ->
        {:error, :invalid_context_subject}
    end
  end

  def context_subject(_operation), do: {:error, :invalid_context_subject}

  @impl true
  def build_context(project, %SubjectRef{kind: :dialogue} = subject_ref, policy, entity_builder),
    do: DialogueContext.build(project, subject_ref, policy, entity_builder)

  def build_context(project, %SubjectRef{kind: :flow_neighborhood} = subject_ref, policy, entity_builder),
    do: FlowNeighborhoodContext.build(project, subject_ref, policy, entity_builder)

  @impl true
  def acquire_source_locks(%Operation{context_subject: %{} = persisted} = operation) do
    case ContextContract.from_persisted_subject(persisted) do
      {:ok, %SubjectRef{}} -> SourceLocks.acquire(operation)
      {:error, :invalid_context_subject} -> {:error, :stale_context}
    end
  end

  def acquire_source_locks(%Operation{}), do: {:error, :stale_context}
end
