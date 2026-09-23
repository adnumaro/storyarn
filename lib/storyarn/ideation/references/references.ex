defmodule Storyarn.Ideation.References do
  @moduledoc "Authorized contextual references owned by brainstorming, never authoring copies."
  alias Storyarn.Ideation.References.Catalog
  alias Storyarn.Ideation.References.ContextualCatalog
  alias Storyarn.Ideation.References.ContextualSession
  alias Storyarn.Ideation.References.Mutation
  alias Storyarn.Ideation.References.Queries.Targets

  defdelegate get(scope, project_id, session_id, idea_id, id), to: Catalog
  defdelegate resume_contextual_session(scope, project_id, type, id, session_id), to: ContextualCatalog, as: :resume
  defdelegate contextual(scope, project_id, type, id, opts), to: ContextualCatalog, as: :get
  defdelegate create_contextual_session(scope, project_id, attrs), to: ContextualSession, as: :create
  defdelegate link_contextual_session(scope, project_id, session_id, attrs), to: ContextualSession, as: :link

  defdelegate list(scope, project_id, session_id, idea_id, opts), to: Catalog
  defdelegate search(scope, project_id, session_id, idea_id, opts), to: Catalog
  defdelegate add(scope, project_id, session_id, idea_id, attrs), to: Mutation
  defdelegate history(scope, project_id, session_id, idea_id, id), to: Catalog
  defdelegate backlinks(scope, project_id, type, id, opts), to: Catalog
  defdelegate targets(scope, project_id, targets), to: Targets, as: :get_many
  defdelegate search_targets(scope, project_id, type, query, opts), to: Targets, as: :search

  def refresh(scope, project_id, session_id, idea_id, id, version, key),
    do: Mutation.change(scope, project_id, session_id, idea_id, id, version, key, "refresh")

  def remove(scope, project_id, session_id, idea_id, id, version, key),
    do: Mutation.change(scope, project_id, session_id, idea_id, id, version, key, "remove")
end
