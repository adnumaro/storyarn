defmodule Storyarn.Ideation.Ideas.Execution.Transaction do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Events.Invalidation
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id, callback) do
    if Repo.in_transaction?() do
      {:error, :idea_requires_outer_transaction}
    else
      fn -> run_locked(scope, project_id, session_id, callback) end
      |> Repo.transact()
      |> complete(project_id, session_id)
    end
  end

  defp run_locked(scope, project_id, session_id, callback) do
    with {:ok, access} <- Sessions.lock_for_contribution(scope, project_id, session_id) do
      callback.(access)
    end
  end

  defp complete({:ok, {result, audiences}}, project_id, session_id) do
    Enum.each(Enum.uniq(audiences), &Invalidation.broadcast(project_id, session_id, &1))
    result
  end

  defp complete({:error, reason}, _project_id, _session_id), do: {:error, reason}

  def success(value, audiences \\ []), do: {:ok, {{:ok, value}, audiences}}
  def conflict(value), do: {:ok, {{:error, {:edit_conflict, value}}, []}}
end
