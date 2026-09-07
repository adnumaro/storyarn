defmodule Storyarn.Ideation.Ideas do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Commands
  alias Storyarn.Ideation.Ideas.Events.Invalidation
  alias Storyarn.Ideation.Ideas.Queries

  defdelegate connect_ideas(scope, project_id, session_id, source_id, target_id, connected?),
    to: Commands.Connect,
    as: :run

  defdelegate delete_idea(scope, project_id, session_id, idea_id, revision), to: Commands.Delete, as: :run

  defdelegate create_idea(scope, project_id, session_id, attrs), to: Commands.Create, as: :run

  defdelegate derive_idea(scope, project_id, session_id, source_id, source_revision, attrs),
    to: Commands.Create,
    as: :derive

  defdelegate update_idea_canvas(scope, project_id, session_id, idea_id, revision, attrs),
    to: Commands.UpdateCanvas,
    as: :run

  defdelegate update_idea(scope, project_id, session_id, idea_id, revision, attrs), to: Commands.Update, as: :run
  defdelegate get_idea(scope, project_id, session_id, idea_id), to: Queries.Get, as: :run
  defdelegate list_ideas(scope, project_id, session_id, opts \\ []), to: Queries.List, as: :run
  defdelegate count_ideas(scope, project_id, session_id), to: Queries.List, as: :counts
  defdelegate list_idea_revisions(scope, project_id, session_id, idea_id, opts \\ []), to: Queries.History, as: :run
  defdelegate list_idea_conflicts(scope, project_id, session_id, idea_id, opts \\ []), to: Queries.Edits, as: :list
  defdelegate get_idea_edit(scope, project_id, session_id, idea_id, key), to: Queries.Edits, as: :get

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

  defdelegate derive_canvas_idea(scope, project_id, session_id, idea_id, revision, attrs),
    to: Commands.Create,
    as: :derive_canvas

  defdelegate update_canvas_idea(scope, project_id, session_id, idea_id, revision, attrs),
    to: Commands.Update,
    as: :run_canvas

  defdelegate set_private_mode(scope, project_id, session_id, revision, enabled), to: Commands.SetPrivateMode, as: :run
end
