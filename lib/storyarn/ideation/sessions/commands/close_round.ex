defmodule Storyarn.Ideation.Sessions.Commands.CloseRound do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, round_id, revision) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      with {:ok, round} <- RoundMutation.get(session.id, round_id) do
        close(session, access, round)
      end
    end)
  end

  defp close(session, _access, %{status: :closed}), do: {:ok, session}
  defp close(_session, _access, %{status: status}) when status in [:planned, :cancelled], do: {:error, :round_not_active}

  defp close(session, access, round) do
    with {:ok, closed} <-
           round
           |> Round.lifecycle_changeset(status: :closed, closed_at: %{TimeHelpers.now() | microsecond: {0, 6}})
           |> Repo.update() do
      RoundMutation.record(session, access, closed, :round_closed)
    end
  end
end
