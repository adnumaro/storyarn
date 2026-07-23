defmodule StoryarnTest.AI.ContextTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent

  @impl true
  def definition do
    %{
      id: "context.test",
      capability: :suggestions,
      data_scope: :entity,
      required_domain_permissions: %{execute: :view, apply: :edit_content},
      allowed_lanes: [:managed],
      input_schema_version: "context-input-v1",
      output_schema_version: "context-output-v1",
      prompt_version: "context-prompt-v1",
      context_version: "context-v1",
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
      result_type: "context_test",
      result_destination: %{type: :panel, id: "context-test"},
      result_ttl_seconds: 300,
      personal_byok_allowed?: false,
      personal_cost_class: nil,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{id: "context-test", version: 1, units: 1},
      enabled?: true,
      command_ids: [],
      provider_options: %{}
    }
  end

  @impl true
  def authorize_subject(_scope, _intent_or_operation, _phase), do: :ok

  @impl true
  def subject_current?(_operation), do: true

  @impl true
  def context_subject(%ExecutionIntent{} = intent) do
    case intent.input do
      %{"context_kind" => "sheet", "sheet_id" => sheet_id} = input ->
        SubjectRef.sheet(intent.workspace_id, intent.project_id, sheet_id, block_ids: Map.get(input, "block_ids", []))

      %{"context_kind" => "flow", "node_id" => node_id} ->
        SubjectRef.flow_neighborhood(intent.workspace_id, intent.project_id, node_id)

      %{"context_kind" => "dialogue", "node_id" => node_id} = input ->
        SubjectRef.dialogue(intent.workspace_id, intent.project_id, node_id, response_id: Map.get(input, "response_id"))

      _input ->
        {:error, :invalid_context_subject}
    end
  end

  def context_subject(_operation), do: {:error, :invalid_context_subject}
end
