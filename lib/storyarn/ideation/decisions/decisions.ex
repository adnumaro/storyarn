defmodule Storyarn.Ideation.Decisions do
  @moduledoc false

  alias Storyarn.Ideation.Decisions.Commands
  alias Storyarn.Ideation.Decisions.Events.Invalidation
  alias Storyarn.Ideation.Decisions.Queries.About
  alias Storyarn.Ideation.Decisions.Queries.Catalog
  alias Storyarn.Ideation.Decisions.Queries.Project
  alias Storyarn.Ideation.Decisions.Queries.Sources
  alias Storyarn.Ideation.Sessions

  defdelegate comment_source(scope, project_id, session_id, decision_id, opts),
    to: Storyarn.Ideation.Decisions.Execution.CommentSource,
    as: :get

  defdelegate comment_sources_query(), to: Storyarn.Ideation.Decisions.Queries.CommentSources, as: :query

  defdelegate preview_sources(scope, project_id, session_id, selections), to: Sources, as: :preview
  defdelegate search_sources(scope, project_id, session_id, opts), to: Sources, as: :search
  defdelegate list(scope, project_id, session_id), to: Catalog
  defdelegate about(scope, project_id, type, id, opts \\ []), to: About, as: :list

  # Readers of the project hear when any of its decisions changes.
  def subscribe_project(scope, project_id) do
    with :ok <- Sessions.authorize_project_read(scope, project_id), do: Invalidation.subscribe(project_id)
  end

  defdelegate list_project(scope, project_id), to: Project, as: :list
  defdelegate session(scope, project_id, id), to: Project
  defdelegate get(scope, project_id, session_id, id), to: Catalog
  defdelegate get_many(scope, project_id, ids), to: Catalog
  defdelegate declarations(scope, project_id, events), to: Catalog
  defdelegate history(scope, project_id, session_id, id), to: Catalog
  defdelegate propose(scope, project_id, session_id, attrs), to: Commands.Propose, as: :run
  defdelegate revise(scope, project_id, session_id, id, version, attrs), to: Commands.Revise, as: :run
  defdelegate accept(scope, project_id, session_id, id, version, key), to: Commands.Accept, as: :run
  defdelegate withdraw(scope, project_id, session_id, id, version, key), to: Commands.Withdraw, as: :run
  defdelegate declare(scope, project_id, session_id, id, agreement, attrs), to: Commands.Declare, as: :run
  defdelegate link_task(scope, project_id, session_id, id, attrs), to: Commands.LinkTask, as: :run
  defdelegate edit_task(scope, project_id, session_id, id, link_key, attrs), to: Commands.EditTask, as: :run
  defdelegate unlink_task(scope, project_id, session_id, id, link_key, key), to: Commands.UnlinkTask, as: :run
end
