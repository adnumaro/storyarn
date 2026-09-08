defmodule Storyarn.Ideation.Sessions.Commands.StartRound do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, round_id, revision) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      with {:ok, round} <- RoundMutation.get(session.id, round_id) do
        start(session, access, round)
      end
    end)
  end

  defp start(session, _access, %{status: :active}), do: {:ok, session}
  defp start(_session, _access, %{status: :closed}), do: {:error, :round_closed}

  defp start(session, access, round) do
    if Repo.exists?(from r in Round, where: r.session_id == ^session.id and r.status == :active) do
      {:error, :round_already_active}
    else
      with {:ok, started} <-
             round
             |> Round.lifecycle_changeset(status: :active, started_at: %{TimeHelpers.now() | microsecond: {0, 6}})
             |> Repo.update() do
        RoundMutation.record(session, access, started, :round_started)
      end
    end
  end
end
