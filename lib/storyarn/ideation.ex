defmodule Storyarn.Ideation do
  @moduledoc """
  Owns brainstorming sessions and their creative collaboration policy.

  This first delivery provides the session foundation, not a released board.
  Every operation requires current project access. All mutations are atomic and
  updates require the revision the caller actually read. Project ownership and
  membership remain authoritative in Projects.
  """

  alias Storyarn.Ideation.Sessions

  defdelegate create_session(scope, project_id, attrs), to: Sessions
  defdelegate list_sessions(scope, project_id, opts \\ []), to: Sessions
  defdelegate get_session(scope, project_id, session_id), to: Sessions

  defdelegate list_session_revisions(scope, project_id, session_id, opts \\ []), to: Sessions

  defdelegate update_session(scope, project_id, session_id, revision, attrs), to: Sessions

  defdelegate assign_session_responsibilities(scope, project_id, session_id, revision, attrs),
    to: Sessions

  defdelegate archive_session(scope, project_id, session_id, revision), to: Sessions
  defdelegate reopen_session(scope, project_id, session_id, revision), to: Sessions
end
