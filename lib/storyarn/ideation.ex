defmodule Storyarn.Ideation do
  @moduledoc """
  Owns brainstorming sessions and their creative collaboration policy.

  This first delivery provides the session foundation, not a released board.
  Every operation requires current project access. All mutations are atomic and
  updates require the revision the caller actually read. Project ownership and
  membership remain authoritative in Projects.
  """

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
end
