defmodule Storyarn.Ideation.Sessions.Execution.RoundMutation do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, callback) do
    Mutation.run(scope, project_id, session_id, revision, fn
      %{status: :archived}, _access -> {:error, :session_archived}
      session, access -> callback.(session, access)
    end)
  end

  def get(session_id, round_id) when is_integer(round_id) and round_id > 0 and round_id <= 9_223_372_036_854_775_807 do
    case Repo.one(from r in Round, where: r.session_id == ^session_id and r.id == ^round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  def get(_session_id, _round_id), do: {:error, :invalid_round}

  def record(session, access, round, action) do
    with {:ok, updated} <- session |> change(revision: session.revision + 1) |> Repo.update() do
      Mutation.record(updated, access.user_id, action, %{
        "round" => %{
          "number" => round.number,
          "prompt" => round.prompt,
          "status" => Atom.to_string(round.status),
          "started_at" => timestamp(round.started_at),
          "closed_at" => timestamp(round.closed_at)
        }
      })
    end
  end

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
