defmodule Storyarn.Ideation.Sessions.Commands.Update do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, attrs) do
    Mutation.run(scope, project_id, session_id, revision, fn session, access ->
      update(session, access, attrs)
    end)
  end

  defp update(%{status: :archived}, _access, _attrs), do: {:error, :session_archived}

  defp update(session, access, attrs) do
    changeset = Session.changeset(session, attrs)

    cond do
      not changeset.valid? ->
        {:error, changeset}

      changeset.changes == %{} ->
        {:ok, session}

      true ->
        changeset = put_change(changeset, :revision, session.revision + 1)

        changeset =
          if changed?(changeset, :configuration),
            do: put_change(changeset, :configuration_version, session.configuration_version + 1),
            else: changeset

        with {:ok, updated} <- Repo.update(changeset) do
          Mutation.record(updated, access.user_id, :updated)
        end
    end
  end
end
