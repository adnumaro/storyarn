defmodule StoryarnTest.AI.ContextWithoutStalenessTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  alias StoryarnTest.AI.ContextTask

  @impl true
  def definition do
    ContextTask.definition()
    |> Map.put(:id, "context.without_staleness")
    |> Map.put(:context_policy, %{
      scope: :structural_finding,
      max_depth: 0,
      max_fan_out: 5,
      max_entities: 10,
      max_bytes: 4_096,
      tokenizer: nil,
      fields: %{}
    })
  end

  @impl true
  def authorize_subject(_scope, _intent_or_operation, _phase), do: :ok

  @impl true
  def context_subject(_intent_or_operation), do: {:error, :invalid_context_subject}
end
