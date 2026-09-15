defmodule Storyarn.Ideation.Sessions.Commands.Archive do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.ArchiveTimer
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Execution.RoundPrivacy
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
    # Archiving freezes publication. End the temporary visibility mask of any
    # private round so past publications can be read, without revealing drafts;
    # comment sources only need waking when a mask actually ended.
    ended = RoundPrivacy.end_masks(session.id)

    with {:ok, timer} <- ArchiveTimer.cancel(session.id),
         {:ok, archived} <- session |> archive_changeset() |> Repo.update(),
         additions = if(timer, do: %{"timer" => TimerMutation.snapshot(timer)}, else: %{}),
         {:ok, recorded} <- Mutation.record(archived, access.user_id, :archived, additions) do
      {:ok, recorded, if(ended > 0, do: :sources, else: :board)}
    end
  end

  defp archive_changeset(session),
    do: change(session, status: :archived, archived_at: TimeHelpers.now(), revision: session.revision + 1)
end
