defmodule Storyarn.Ideation.Sessions.Commands.Create do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # A session is born with its first round already in progress, so notes always
  # have a band to live in. The round stays implicit until a second one exists.
  def run(scope, project_id, attrs) do
    Mutation.create(scope, project_id, fn access ->
      session = %Session{
        project_id: access.project_id,
        created_by_id: access.user_id,
        facilitator_id: access.user_id,
        decision_owner_id: access.user_id
      }

      with {:ok, session} <- session |> Session.changeset(attrs) |> Repo.insert(),
           {:ok, _round} <- Repo.insert(first_round(session)) do
        Mutation.record(session, access.user_id, :created)
      end
    end)
  end

  defp first_round(session) do
    %Round{
      session_id: session.id,
      number: 1,
      status: :active,
      started_at: %{TimeHelpers.now() | microsecond: {0, 6}},
      canvas_offset_y: 0
    }
  end
end
