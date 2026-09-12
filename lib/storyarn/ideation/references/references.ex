defmodule Storyarn.Ideation.References do
  @moduledoc "Authorized contextual references owned by brainstorming, never authoring copies."
  alias Storyarn.Ideation.References.Catalog
  alias Storyarn.Ideation.References.Mutation

  defdelegate list(scope, project_id, session_id, idea_id, opts), to: Catalog
  defdelegate search(scope, project_id, session_id, idea_id, opts), to: Catalog
  defdelegate add(scope, project_id, session_id, idea_id, attrs), to: Mutation
  defdelegate history(scope, project_id, session_id, idea_id, id), to: Catalog
  defdelegate backlinks(scope, project_id, type, id, opts), to: Catalog

  def refresh(scope, project_id, session_id, idea_id, id, version, key),
    do: Mutation.change(scope, project_id, session_id, idea_id, id, version, key, "refresh")

  def remove(scope, project_id, session_id, idea_id, id, version, key),
    do: Mutation.change(scope, project_id, session_id, idea_id, id, version, key, "remove")
end
