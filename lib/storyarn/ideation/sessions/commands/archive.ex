defmodule Storyarn.Ideation.Sessions.Commands.Archive do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision) do
    Mutation.run(scope, project_id, session_id, revision, fn
      %{status: :archived} = session, _access ->
        {:ok, session}

      session, access ->
        with {:ok, archived} <-
               session
               |> change(status: :archived, archived_at: TimeHelpers.now(), revision: session.revision + 1)
               |> Repo.update() do
          Mutation.record(archived, access.user_id, :archived)
        end
    end)
  end
end
