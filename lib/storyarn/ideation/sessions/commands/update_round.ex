defmodule Storyarn.Ideation.Sessions.Commands.UpdateRound do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Repo

  def run(scope, project_id, session_id, round_id, revision, attrs) when is_map(attrs) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      with {:ok, round} <- RoundMutation.get(session.id, round_id) do
        update(session, access, round, attrs)
      end
    end)
  end

  def run(_scope, _project_id, _session_id, _round_id, _revision, _attrs), do: {:error, :invalid_round}

  defp update(session, access, %{status: :planned} = round, attrs) do
    changeset = Round.changeset(round, attrs)

    cond do
      not changeset.valid? -> {:error, changeset}
      changeset.changes == %{} -> {:ok, session}
      true -> persist(session, access, changeset)
    end
  end

  defp update(_session, _access, _round, _attrs), do: {:error, :round_not_planned}

  defp persist(session, access, changeset) do
    with {:ok, updated} <- Repo.update(changeset) do
      RoundMutation.record(session, access, updated, :round_updated)
    end
  end
end
