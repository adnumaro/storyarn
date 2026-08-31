defmodule StoryarnTest.AI.VolatileSubjectTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  @impl true
  def definition do
    %{
      id: "volatile.subject",
      capability: :suggestions,
      data_scope: :entity,
      required_domain_permissions: %{execute: :view, apply: :edit_content},
      allowed_lanes: [:managed],
      input_schema_version: "volatile-subject-input-v1",
      output_schema_version: "volatile-subject-output-v1",
      prompt_version: "volatile-subject-prompt-v1",
      context_version: "none-v1",
      context_policy: %{scope: :none},
      max_input_bytes: 1_024,
      max_output_bytes: 1_024,
      execution_mode: :background,
      timeout_ms: 1_000,
      result_type: "volatile_subject_test",
      result_destination: %{type: :panel, id: "volatile-subject-test"},
      result_ttl_seconds: 300,
      personal_byok_allowed?: false,
      personal_cost_class: nil,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{id: "volatile-subject-test", version: 1, units: 1},
      enabled?: true,
      command_ids: [],
      provider_options: %{}
    }
  end

  @impl true
  def post_operation_authorization_mode, do: :lock_free

  @impl true
  def authorize_subject(_scope, _intent_or_operation, _phase) do
    runtime_option(:authorize_subject, :ok)
  end

  @impl true
  def subject_current?(_operation) do
    runtime_option(:subject_current?, true)
  end

  defp runtime_option(key, default) do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
