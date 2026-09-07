defmodule Storyarn.Ideation.Sessions.Commands.Create do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def run(scope, project_id, attrs) do
    Mutation.create(scope, project_id, fn access ->
      session = %Session{
        project_id: access.project_id,
        created_by_id: access.user_id,
        facilitator_id: access.user_id,
        decision_owner_id: access.user_id
      }

      with {:ok, session} <- session |> Session.changeset(attrs) |> Repo.insert() do
        Mutation.record(session, access.user_id, :created)
      end
    end)
  end
end
