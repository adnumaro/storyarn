defmodule StoryarnTest.AI.UnsafeContextTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  alias StoryarnTest.Flows.AI.ContextTask

  @impl true
  def definition do
    Map.put(ContextTask.definition(), :id, "unsafe.context.test")
  end

  @impl true
  def post_operation_authorization_mode, do: :unsafe

  @impl true
  def authorize_subject(scope, intent_or_operation, phase) do
    ContextTask.authorize_subject(scope, intent_or_operation, phase)
  end

  @impl true
  def subject_current?(operation), do: ContextTask.subject_current?(operation)

  @impl true
  def context_contract(policy), do: ContextTask.context_contract(policy)

  @impl true
  def context_subject(intent_or_operation), do: ContextTask.context_subject(intent_or_operation)

  @impl true
  def build_context(project, subject_ref, policy, entity_builder) do
    ContextTask.build_context(project, subject_ref, policy, entity_builder)
  end

  @impl true
  def acquire_source_locks(operation), do: ContextTask.acquire_source_locks(operation)
end
