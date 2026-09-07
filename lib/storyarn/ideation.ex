defmodule Storyarn.Ideation do
  @moduledoc """
  Owns brainstorming sessions and their creative collaboration policy.

  Provides sessions, authored ideas, recoverable saves and explicit publication,
  not a released board. Private drafts remain author-only; other readers receive
  published revisions through authorized projections.
  Every operation requires current project access. All mutations are atomic and
  updates require the revision the caller actually read. Project ownership and
  membership remain authoritative in Projects.
  """

  alias Storyarn.Ideation.Ideas
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

  defdelegate create_idea(scope, project_id, session_id, attrs), to: Ideas
  defdelegate derive_idea(scope, project_id, session_id, source_id, source_revision, attrs), to: Ideas
  defdelegate update_idea(scope, project_id, session_id, idea_id, revision, attrs), to: Ideas
  defdelegate get_idea(scope, project_id, session_id, idea_id), to: Ideas
  defdelegate list_ideas(scope, project_id, session_id, opts \\ []), to: Ideas
  defdelegate count_ideas(scope, project_id, session_id), to: Ideas
  defdelegate list_idea_revisions(scope, project_id, session_id, idea_id, opts \\ []), to: Ideas
  defdelegate list_idea_conflicts(scope, project_id, session_id, idea_id, opts \\ []), to: Ideas
  defdelegate get_idea_edit(scope, project_id, session_id, idea_id, key), to: Ideas
  defdelegate prepare_idea_reveal(scope, project_id, session_id, key, selection \\ :eligible), to: Ideas
  defdelegate reveal_ideas(scope, project_id, session_id, operation_id), to: Ideas
  defdelegate get_idea_reveal(scope, project_id, session_id, operation_id), to: Ideas
  defdelegate subscribe_ideas(scope, project_id, session_id), to: Ideas
end
