defmodule Storyarn.Ideation.Sessions do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Commands
  alias Storyarn.Ideation.Sessions.Queries

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

  # Internal capability port: the caller owns the transaction, Sessions owns
  # project access and the session lifecycle lock. Not exposed by Ideation.
  defdelegate lock_for_contribution(scope, project_id, session_id),
    to: Storyarn.Ideation.Sessions.Execution.ContributionAccess,
    as: :lock
end
