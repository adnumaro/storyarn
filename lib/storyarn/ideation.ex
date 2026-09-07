defmodule Storyarn.Ideation do
  @moduledoc """
  Owns brainstorming sessions and their creative collaboration policy.

  Provides sessions, authored ideas, recoverable saves and explicit publication,
  not a released board. Private drafts remain author-only; other readers receive
  published revisions through authorized projections.
  Every ordinary operation requires current project access. All mutations are atomic and
  updates require the revision the caller actually read. Project ownership and
  membership remain authoritative in Projects.
  """

  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Recovery
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

  defdelegate recover_session(scope, project_id, session_id, revision), to: Sessions

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

  @doc """
  Captures a sealed Ideation recovery capsule. Privileged Project capture port:
  the caller owns the authorized transaction and exclusive Project row lock.
  Returns ciphertext only, including author identities and publication metadata.
  """
  @spec capture_recovery(integer()) :: {:ok, map()} | {:error, atom()}
  defdelegate capture_recovery(project_id), to: Recovery, as: :capture

  @doc false
  @spec validate_recovery(map() | nil) :: :ok | {:error, atom()}
  defdelegate validate_recovery(capsule), to: Recovery, as: :validate

  @doc """
  Reconstitutes a validated, sealed capsule inside the authorized Project restore
  transaction and exclusive Project lock. Never grants access or publishes ideas.
  Existing sessions move to recovery trash; caller must roll back on any error.
  """
  @spec restore_recovery(integer(), map() | nil) :: {:ok, map()} | {:error, atom()}
  defdelegate restore_recovery(project_id, capsule), to: Recovery, as: :restore

  @doc false
  @spec verify_recovery(integer(), map() | nil, map()) :: :ok | {:error, atom()}
  defdelegate verify_recovery(project_id, capsule, maps), to: Recovery, as: :verify
end
