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

  alias Storyarn.Ideation.Decisions
  alias Storyarn.Ideation.Groups
  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Recovery
  alias Storyarn.Ideation.References
  alias Storyarn.Ideation.Sessions

  @doc "Previews only currently shared sources for an explicit decision proposal."
  defdelegate preview_decision_sources(scope, project_id, session_id, sources), to: Decisions, as: :preview_sources

  @doc "Searches shared idea and group sources with bounded cursor pagination."
  defdelegate search_decision_sources(scope, project_id, session_id, opts \\ []), to: Decisions, as: :search_sources

  @doc "Lists readable decisions with their current proposal and last accepted agreement."
  defdelegate list_decisions(scope, project_id, session_id, opts \\ []), to: Decisions, as: :list

  @doc "Reads a decision and its retained agreement using current session and source access."
  defdelegate get_decision(scope, project_id, session_id, id), to: Decisions, as: :get

  @doc "Lists immutable authored proposals and explicit acceptances, with bounded pagination."
  defdelegate decision_history(scope, project_id, session_id, id, opts \\ []), to: Decisions, as: :history

  @doc "Proposes a decision from exact shared source previews without publishing private content."
  defdelegate propose_decision(scope, project_id, session_id, attrs), to: Decisions, as: :propose

  @doc "Creates a revised proposal while preserving the last accepted agreement."
  defdelegate revise_decision(scope, project_id, session_id, id, version, attrs), to: Decisions, as: :revise

  @doc "Records explicit acceptance only by the assigned responsible editor."
  defdelegate accept_decision(scope, project_id, session_id, id, version, key), to: Decisions, as: :accept

  @doc "Opens an authorized editor context with linked explorations and available open sessions."
  defdelegate get_contextual_brainstorming(scope, project_id, type, id, opts \\ []),
    to: References,
    as: :contextual

  @doc "Resumes a readable session only when its whole-session reference still matches the editor context."
  defdelegate resume_contextual_session(scope, project_id, type, id, session_id), to: References

  @doc "Reads one authorized contextual reference, including changed or unavailable status."
  defdelegate get_reference(scope, project_id, session_id, idea_id, id), to: References, as: :get

  @doc "Creates a session and its consulted origin atomically, with a durable retry identity."
  defdelegate create_contextual_session(scope, project_id, attrs), to: References

  @doc "Links an existing open session to an editor context without duplicating an existing session link."
  defdelegate link_contextual_session(scope, project_id, session_id, attrs), to: References

  @doc "Lists contextual references for a shared session or published idea, reauthorizing both endpoints."
  defdelegate list_references(scope, project_id, session_id, idea_id, opts \\ []), to: References, as: :list

  @doc "Searches readable, same-project reference targets without copying an author's private draft."
  defdelegate search_reference_targets(scope, project_id, session_id, idea_id, opts \\ []), to: References, as: :search

  @doc "Explicitly links a shared source to existing content and records its bounded overview."
  defdelegate add_reference(scope, project_id, session_id, idea_id, attrs), to: References, as: :add

  @doc "Explicitly refreshes the consulted context while retaining every previous context revision."
  defdelegate refresh_reference(scope, project_id, session_id, idea_id, id, version, key), to: References, as: :refresh

  @doc "Removes a link, retaining its provenance without editing or deleting the destination."
  defdelegate remove_reference(scope, project_id, session_id, idea_id, id, version, key), to: References, as: :remove

  @doc "Reads retained context revisions only while both endpoints remain available to the caller."
  defdelegate reference_history(scope, project_id, session_id, idea_id, id), to: References, as: :history

  @doc "Lists currently readable backlinks without exposing private ideas or historical target previews."
  defdelegate list_reference_backlinks(scope, project_id, type, id, opts \\ []), to: References, as: :backlinks

  @doc "Shared identity and label projections for authorized comment queries; excludes idea/group creative content."
  def comment_sources_query("ideation_session"), do: Sessions.comment_sources_query()
  def comment_sources_query("ideation_idea"), do: Ideas.comment_sources_query()
  def comment_sources_query("ideation_group"), do: Groups.comment_sources_query()

  @doc "Resolves a shared group comment source without publishing group text or member revisions."
  defdelegate group_comment_source(scope, project_id, session_id, group_id, opts \\ []), to: Groups, as: :comment_source

  @doc "Resolves a session or published idea comment anchor without exposing private revisions."
  defdelegate comment_source(scope, project_id, session_id, idea_id, opts \\ []),
    to: Ideas

  @doc "Lists shared canvas groups and live source geometry; private mode hides all synthesis."
  @spec list_groups(map(), pos_integer(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  defdelegate list_groups(scope, project_id, session_id), to: Groups

  @doc "Groups at least two shared notes while retaining pinned source provenance."
  @spec create_group(map(), pos_integer(), pos_integer(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate create_group(scope, project_id, session_id, attrs), to: Groups

  @doc "Edits a group's text and membership with optimistic concurrency and durable request identity."
  @spec update_group(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate update_group(scope, project_id, session_id, id, version, attrs), to: Groups

  @doc "Moves the group and every live source atomically, rejecting stale member placements."
  @spec move_group(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate move_group(scope, project_id, session_id, id, version, attrs), to: Groups

  @doc "Deletes a group container while preserving every source idea."
  @spec delete_group(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defdelegate delete_group(scope, project_id, session_id, id, version, request_key), to: Groups

  @doc "Undoes the acting editor's exact group deletion without replacing arbitrary history."
  @spec restore_group(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate restore_group(scope, project_id, session_id, id, version, attrs), to: Groups

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

  @doc "Reads round context and the session timer after one current access check."
  @spec get_canvas_context(map(), pos_integer(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate get_canvas_context(scope, project_id, session_id, opts \\ []), to: Sessions

  @doc "Reads the current shared timer for an authorized session participant."
  @spec get_timer(map(), pos_integer(), pos_integer()) :: {:ok, struct() | nil} | {:error, term()}
  defdelegate get_timer(scope, project_id, session_id), to: Sessions

  @doc "Starts an independent timer with explicitly selected expiry actions."
  @spec start_timer(map(), pos_integer(), pos_integer(), pos_integer(), map()) :: {:ok, struct()} | {:error, term()}
  defdelegate start_timer(scope, project_id, session_id, revision, attrs), to: Sessions

  @doc "Pauses the current timer and invalidates its previous deadline."
  @spec pause_timer(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate pause_timer(scope, project_id, session_id, revision, timer_version), to: Sessions

  @doc "Resumes a paused timer after reauthorizing its selected actions."
  @spec resume_timer(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate resume_timer(scope, project_id, session_id, revision, timer_version), to: Sessions

  @doc "Adds time while fencing any expiration scheduled for the previous version."
  @spec extend_timer(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate extend_timer(scope, project_id, session_id, revision, timer_version, seconds), to: Sessions

  @doc "Cancels a timer without applying its expiry actions."
  @spec cancel_timer(map(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate cancel_timer(scope, project_id, session_id, revision, timer_version), to: Sessions

  @doc "Controls admission of new notes while preserving edits to existing contributions."
  @spec set_contributions_open(map(), pos_integer(), pos_integer(), pos_integer(), boolean()) ::
          {:ok, struct()} | {:error, term()}
  defdelegate set_contributions_open(scope, project_id, session_id, revision, open), to: Sessions

  @doc false
  @spec expire_timer(pos_integer(), pos_integer()) :: {:ok, map()} | {:error, term()}
  defdelegate expire_timer(timer_id, version), to: Sessions

  @doc false
  @spec timer_runtime_child_specs() :: [Supervisor.child_spec()]
  defdelegate timer_runtime_child_specs(), to: Sessions

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

  @doc "Atomically updates readable canvas connections using independent source versions and a bounded retry receipt."
  @spec update_idea_connections(map(), pos_integer(), pos_integer(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate update_idea_connections(scope, project_id, session_id, attrs), to: Ideas

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
  @spec restore_recovery(integer(), map() | nil, map() | nil) :: {:ok, map()} | {:error, atom()}
  defdelegate restore_recovery(project_id, capsule, destination_maps \\ nil), to: Recovery, as: :restore

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
