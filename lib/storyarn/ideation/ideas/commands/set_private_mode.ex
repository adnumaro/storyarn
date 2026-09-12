defmodule Storyarn.Ideation.Ideas.Commands.SetPrivateMode do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Execution.PrivateMode
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Sessions

  def run(scope, project_id, session_id, revision, enabled) when is_boolean(enabled) do
    result =
      Transaction.run(scope, project_id, session_id, &set_locked(&1, revision, enabled))

    Sessions.notify_canvas_mode(result, project_id)
  end

  def run(_, _, _, _, _), do: {:error, :invalid_parameters}

  defp set_locked(access, revision, enabled) do
    with {:ok, result} <- PrivateMode.set_locked(access, revision, enabled) do
      audiences = if result.changed, do: [:shared, :comment_sources], else: []
      Transaction.success(%{id: access.session_id, private_mode: enabled}, audiences)
    end
  end
end
