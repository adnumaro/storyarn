defmodule Storyarn.Ideation.Sessions.Commands.Reopen do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision) do
    Mutation.run(scope, project_id, session_id, revision, fn
      %{status: :open} = session, _access ->
        {:ok, session}

      session, access ->
        with {:ok, reopened} <-
               session
               |> change(status: :open, archived_at: nil, revision: session.revision + 1)
               |> Repo.update() do
          Mutation.record(reopened, access.user_id, :reopened)
        end
    end)
  end
end
