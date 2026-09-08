defmodule Storyarn.Ideation.Sessions.Commands.CreateRound do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, attrs) when is_map(attrs) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      last_number = Repo.one(from r in Round, where: r.session_id == ^session.id, select: max(r.number)) || 0

      with {:ok, round} <-
             %Round{session_id: session.id, number: last_number + 1}
             |> Round.changeset(attrs)
             |> Repo.insert() do
        RoundMutation.record(session, access, round, :round_created)
      end
    end)
  end

  def run(_scope, _project_id, _session_id, _revision, _attrs), do: {:error, :invalid_round}
end
