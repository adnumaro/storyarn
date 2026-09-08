defmodule Storyarn.Ideation.Sessions.Commands.SetContributionsOpen do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, enabled) when is_boolean(enabled) do
    Mutation.run(scope, project_id, session_id, revision, fn
      %{status: :archived}, _ ->
        {:error, :session_archived}

      %{contributions_open: ^enabled} = session, _ ->
        {:ok, session}

      session, access ->
        set_open(session, access, enabled)
    end)
  end

  def run(_, _, _, _, _), do: {:error, :invalid_parameters}

  defp set_open(session, access, enabled) do
    action = if enabled, do: :contributions_opened, else: :contributions_closed

    with {:ok, updated} <-
           session |> change(contributions_open: enabled, revision: session.revision + 1) |> Repo.update() do
      Mutation.record(updated, access.user_id, action)
    end
  end
end
