defmodule Storyarn.Ideation do
  @moduledoc """
  Owns brainstorming sessions and their creative collaboration policy.

  Provides sessions, authored canvas ideas, recoverable saves and facilitator-controlled
  visibility. Private-mode contributions remain author-only until the facilitator
  reveals them; other readers receive authorized published revisions.
  Every ordinary operation requires current project access. All mutations are atomic and
  updates require the revision the caller actually read. Project ownership and
  membership remain authoritative in Projects.
  """

  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Recovery
  alias Storyarn.Ideation.Sessions

  defdelegate create_session(scope, project_id, attrs), to: Sessions
  defdelegate subscribe_sessions(scope, project_id), to: Sessions
  defdelegate list_sessions(scope, project_id, opts \\ []), to: Sessions
  defdelegate get_session(scope, project_id, session_id), to: Sessions

  @doc "Lists optional rounds from a readable session, newest first, with bounded cursor pagination."
  @spec list_rounds(map(), pos_integer(), pos_integer(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  defdelegate list_rounds(scope, project_id, session_id, opts \\ []), to: Sessions

  @doc "Reads a round history range and its active and referenced context after one access check."
  @spec get_round_context(map(), pos_integer(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate get_round_context(scope, project_id, session_id, opts \\ []), to: Sessions

  @doc "Prepares an optional round without starting a timer or changing session visibility."
  @spec create_round(map(), pos_integer(), pos_integer(), pos_integer(), map()) :: {:ok, struct()} | {:error, term()}
  defdelegate create_round(scope, project_id, session_id, revision, attrs), to: Sessions

  @doc "Edits a prepared round's question after checking current facilitator authority and session revision."
  @spec update_round(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate update_round(scope, project_id, session_id, round_id, revision, attrs), to: Sessions

  @doc "Cancels a prepared round while retaining its session record and recovery provenance."
  @spec cancel_round(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate cancel_round(scope, project_id, session_id, round_id, revision), to: Sessions

  @doc "Starts a prepared round after checking facilitator authority and the current session revision."
  @spec start_round(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate start_round(scope, project_id, session_id, round_id, revision), to: Sessions

  @doc "Closes the active round without publishing ideas or restricting further contribution and editing."
  @spec close_round(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate close_round(scope, project_id, session_id, round_id, revision), to: Sessions

  defdelegate list_session_revisions(scope, project_id, session_id, opts \\ []), to: Sessions

  defdelegate update_session(scope, project_id, session_id, revision, attrs), to: Sessions

  defdelegate assign_session_responsibilities(scope, project_id, session_id, revision, attrs),
    to: Sessions

  defdelegate archive_session(scope, project_id, session_id, revision), to: Sessions
  defdelegate reopen_session(scope, project_id, session_id, revision), to: Sessions

  defdelegate recover_session(scope, project_id, session_id, revision), to: Sessions

  @doc "Connects or disconnects two readable ideas in the same session."
  @spec connect_ideas(map(), integer(), integer(), integer(), integer(), boolean()) :: {:ok, map()} | {:error, term()}
  defdelegate connect_ideas(scope, project_id, session_id, source_id, target_id, connected?), to: Ideas

  @doc "Updates an authorized idea's canvas placement, independently of its text revision."
  @spec update_idea_canvas(map(), integer(), integer(), integer(), non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate update_idea_canvas(scope, project_id, session_id, idea_id, revision, attrs), to: Ideas

  @doc "Permanently deletes one replaced session after checking current project ownership and its revision."
  @spec purge_replaced_session(map(), pos_integer(), pos_integer(), pos_integer()) :: {:ok, :purged} | {:error, term()}
  defdelegate purge_replaced_session(scope, project_id, session_id, revision), to: Sessions

  defdelegate create_idea(scope, project_id, session_id, attrs), to: Ideas
  defdelegate update_idea(scope, project_id, session_id, idea_id, revision, attrs), to: Ideas
  defdelegate get_idea(scope, project_id, session_id, idea_id), to: Ideas
  defdelegate list_ideas(scope, project_id, session_id, opts \\ []), to: Ideas
  defdelegate count_ideas(scope, project_id, session_id, opts \\ []), to: Ideas
  defdelegate prepare_idea_reveal(scope, project_id, session_id, key, selection \\ :eligible), to: Ideas
  defdelegate reveal_ideas(scope, project_id, session_id, operation_id), to: Ideas
  defdelegate get_idea_reveal(scope, project_id, session_id, operation_id), to: Ideas
  defdelegate subscribe_ideas(scope, project_id, session_id), to: Ideas
  defdelegate unsubscribe_ideas(scope, project_id, session_id), to: Ideas

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
  @doc "Removes an authored note from all current views while retaining its recovery history."
  @spec delete_idea(map(), integer(), integer(), integer(), integer()) :: {:ok, map()} | {:error, term()}
  defdelegate delete_idea(scope, project_id, session_id, idea_id, revision), to: Ideas

  @doc "Undoes the author's exact canvas deletion without restoring arbitrary historical content."
  @spec restore_idea(map(), integer(), integer(), integer(), integer(), DateTime.t() | String.t()) ::
          {:ok, map()} | {:error, term()}
  defdelegate restore_idea(scope, project_id, session_id, idea_id, revision, deleted_at), to: Ideas

  @doc "Creates a canvas contribution under the current session visibility mode."
  @spec create_canvas_idea(map(), integer(), integer(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate create_canvas_idea(scope, project_id, session_id, attrs), to: Ideas
  @doc "Saves a canvas note and publishes that revision atomically in shared mode."
  @spec update_canvas_idea(map(), integer(), integer(), integer(), integer(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate update_canvas_idea(scope, project_id, session_id, idea_id, revision, attrs), to: Ideas
  @doc "Lets the facilitator change private mode for everyone; ending it reveals current contributions atomically."
  @spec set_private_mode(map(), integer(), integer(), integer(), boolean()) :: {:ok, map()} | {:error, term()}
  defdelegate set_private_mode(scope, project_id, session_id, revision, enabled), to: Ideas
end
