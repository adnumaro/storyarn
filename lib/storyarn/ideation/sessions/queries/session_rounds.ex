defmodule Storyarn.Ideation.Sessions.Queries.SessionRounds do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.ProjectAccess
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  @max_sessions 200

  # Rounds of several sessions in one read, for the session tree. Project read
  # access is the boundary: every listed session must belong to that project.
  def run(scope, project_id, session_ids) when is_list(session_ids) and length(session_ids) <= @max_sessions do
    with :ok <- ProjectAccess.authorize(scope, project_id),
         true <- Enum.all?(session_ids, &valid_id/1) do
      rounds =
        Repo.all(
          from r in Round,
            join: s in Session,
            on: s.id == r.session_id,
            where: s.project_id == ^project_id and r.session_id in ^session_ids,
            order_by: [asc: r.session_id, asc: r.number]
        )

      {:ok, Enum.group_by(rounds, & &1.session_id)}
    else
      false -> {:error, :invalid_options}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_scope, _project_id, _session_ids), do: {:error, :invalid_options}

  defp valid_id(id), do: is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
end
