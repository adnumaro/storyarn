defmodule Storyarn.Ideation.Ideas do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Commands
  alias Storyarn.Ideation.Ideas.Events.Invalidation
  alias Storyarn.Ideation.Ideas.Queries

  defdelegate comment_sources_query(), to: Storyarn.Ideation.Ideas.Queries.CommentSources, as: :query

  defdelegate comment_source(scope, project_id, session_id, idea_id, opts),
    to: Storyarn.Ideation.Ideas.Execution.CommentSource,
    as: :get

  @doc false
  @spec group_sources(pos_integer(), [pos_integer()]) :: [map()]
  defdelegate group_sources(session_id, ids), to: Queries.GroupSources, as: :list

  @doc false
  @spec move_group_sources(map(), [pos_integer()], map(), number(), number()) :: :ok | {:error, atom()}
  defdelegate move_group_sources(access, ids, versions, dx, dy),
    to: Storyarn.Ideation.Ideas.Execution.GroupPlacement,
    as: :move

  defdelegate set_private_mode_locked(access, revision, enabled),
    to: Storyarn.Ideation.Ideas.Execution.PrivateMode,
    as: :set_locked

  def notify_timer_reveal(project_id, session_id), do: Invalidation.broadcast(project_id, session_id, :shared)

  defdelegate connect_ideas(scope, project_id, session_id, source_id, target_id, connected?),
    to: Commands.Connect,
    as: :run

  defdelegate update_idea_connections(scope, project_id, session_id, attrs), to: Commands.UpdateConnections, as: :run

  defdelegate delete_idea(scope, project_id, session_id, idea_id, revision), to: Commands.Delete, as: :run

  defdelegate restore_idea(scope, project_id, session_id, idea_id, revision, deleted_at),
    to: Commands.Restore,
    as: :run

  defdelegate create_idea(scope, project_id, session_id, attrs), to: Commands.Create, as: :run

  defdelegate update_idea_canvas(scope, project_id, session_id, idea_id, revision, attrs),
    to: Commands.UpdateCanvas,
    as: :run

  defdelegate update_idea(scope, project_id, session_id, idea_id, revision, attrs), to: Commands.Update, as: :run
  defdelegate get_idea(scope, project_id, session_id, idea_id), to: Queries.Get, as: :run
  defdelegate list_ideas(scope, project_id, session_id, opts \\ []), to: Queries.List, as: :run
  defdelegate count_ideas(scope, project_id, session_id, opts \\ []), to: Queries.List, as: :counts

  defdelegate prepare_idea_reveal(scope, project_id, session_id, key, selection \\ :eligible),
    to: Commands.PrepareReveal,
    as: :run

  defdelegate reveal_ideas(scope, project_id, session_id, operation_id), to: Commands.Reveal, as: :run
  defdelegate get_idea_reveal(scope, project_id, session_id, operation_id), to: Queries.Reveal, as: :run

  def subscribe_ideas(scope, project_id, session_id) do
    with {:ok, actor_id} <- Queries.Access.authorize(scope, project_id, session_id) do
      Invalidation.subscribe(project_id, session_id, actor_id)
    end
  end

  def unsubscribe_ideas(scope, project_id, session_id),
    do: Invalidation.unsubscribe(project_id, session_id, scope.user.id)

  defdelegate create_canvas_idea(scope, project_id, session_id, attrs), to: Commands.Create, as: :run_canvas

  defdelegate update_canvas_idea(scope, project_id, session_id, idea_id, revision, attrs),
    to: Commands.Update,
    as: :run_canvas

  defdelegate set_private_mode(scope, project_id, session_id, revision, enabled), to: Commands.SetPrivateMode, as: :run
end
