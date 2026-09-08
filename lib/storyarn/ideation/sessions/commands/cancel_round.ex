defmodule Storyarn.Ideation.Sessions.Commands.CancelRound do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  def run(scope, project_id, session_id, round_id, revision) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      with {:ok, round} <- RoundMutation.get(session.id, round_id) do
        cancel(session, access, round)
      end
    end)
  end

  defp cancel(session, access, %{status: :planned} = round) do
    with {:ok, cancelled} <- round |> Round.lifecycle_changeset(status: :cancelled) |> Repo.update() do
      RoundMutation.record(session, access, cancelled, :round_cancelled)
    end
  end

  defp cancel(session, _access, %{status: :cancelled}), do: {:ok, session}
  defp cancel(_session, _access, _round), do: {:error, :round_not_planned}
end
