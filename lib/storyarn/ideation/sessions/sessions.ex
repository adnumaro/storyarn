defmodule Storyarn.Ideation.Sessions do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Commands
  alias Storyarn.Ideation.Sessions.Events.Invalidation
  alias Storyarn.Ideation.Sessions.Queries

  def subscribe_sessions(scope, project_id) do
    with :ok <- Queries.ProjectAccess.authorize(scope, project_id), do: Invalidation.subscribe(project_id)
  end

  defdelegate create_session(scope, project_id, attrs), to: Commands.Create, as: :run
  defdelegate list_sessions(scope, project_id, opts \\ []), to: Queries.List, as: :run
  defdelegate get_session(scope, project_id, session_id), to: Queries.Get, as: :run

  defdelegate list_session_revisions(scope, project_id, session_id, opts \\ []),
    to: Queries.History,
    as: :run

  defdelegate update_session(scope, project_id, session_id, revision, attrs), to: Commands.Update, as: :run

  defdelegate assign_session_responsibilities(scope, project_id, session_id, revision, attrs),
    to: Commands.AssignResponsibilities,
    as: :run

  defdelegate archive_session(scope, project_id, session_id, revision), to: Commands.Archive, as: :run
  defdelegate reopen_session(scope, project_id, session_id, revision), to: Commands.Reopen, as: :run

  defdelegate recover_session(scope, project_id, session_id, revision), to: Commands.Recover, as: :run
  defdelegate purge_replaced_session(scope, project_id, session_id, revision), to: Commands.PurgeReplaced, as: :run

  defdelegate set_canvas_mode_locked(access, revision, enabled),
    to: Storyarn.Ideation.Sessions.Execution.CanvasMode,
    as: :set

  defdelegate notify_canvas_mode(result, project_id), to: Invalidation, as: :notify

  defdelegate canvas_settings_query(), to: Queries.CanvasSettings, as: :query

  # Internal capability port: the caller owns the transaction, Sessions owns
  # project access and the session lifecycle lock. Not exposed by Ideation.
  defdelegate lock_for_contribution(scope, project_id, session_id),
    to: Storyarn.Ideation.Sessions.Execution.ContributionAccess,
    as: :lock
end
