defmodule Storyarn.Ideation.Decisions.Adapters.Notifications do
  @moduledoc false
  alias Storyarn.Platform
  alias Storyarn.Projects

  # Joins the decision's transaction; publish only after it commits.
  def deliver(_actor_id, _project_id, _decision, []), do: {:ok, nil}

  def deliver(actor_id, project_id, decision, recipients),
    do: Platform.deliver_decision_activity(actor_id, project_id, decision, recipients)

  def publish(nil), do: :ok
  def publish(outcome), do: Platform.publish_notification_delivery(outcome)

  # Everyone who started a thread about the decision takes part in its discussion.
  def discussants(scope, project_id, session_id, decision_id) do
    case Projects.list_ideation_comment_threads(scope, project_id, session_id, {:decision, decision_id}, limit: 100) do
      {:ok, %{threads: threads}} -> threads |> Enum.map(& &1.author.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      _ -> []
    end
  end
end
