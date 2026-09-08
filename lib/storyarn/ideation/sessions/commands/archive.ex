defmodule Storyarn.Ideation.Sessions.Commands.Archive do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.ArchiveTimer
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision) do
    scope
    |> Mutation.run(project_id, session_id, revision, fn
      %{status: :archived} = session, _access ->
        {:ok, session}

      session, access ->
        archive(session, access)
    end)
    |> TimerInvalidation.notify()
  end

  defp archive(session, access) do
    with {:ok, timer} <- ArchiveTimer.cancel(session.id),
         {:ok, archived} <- session |> archive_changeset() |> Repo.update() do
      additions = if timer, do: %{"timer" => TimerMutation.snapshot(timer)}, else: %{}
      Mutation.record(archived, access.user_id, :archived, additions)
    end
  end

  defp archive_changeset(session) do
    changeset = change(session, status: :archived, archived_at: TimeHelpers.now(), revision: session.revision + 1)

    # Archiving freezes publication. End the temporary visibility mask so past
    # publications can be read, but never publish any new private draft.
    if session.configuration.private_mode do
      changeset
      |> change(configuration_version: session.configuration_version + 1)
      |> put_embed(:configuration, %{private_mode: false})
    else
      changeset
    end
  end
end
