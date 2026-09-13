defmodule Storyarn.Ideation.Decisions do
  @moduledoc false

  alias Storyarn.Ideation.Decisions.Commands
  alias Storyarn.Ideation.Decisions.Queries.Catalog
  alias Storyarn.Ideation.Decisions.Queries.Sources

  defdelegate preview_sources(scope, project_id, session_id, selections), to: Sources, as: :preview
  defdelegate search_sources(scope, project_id, session_id, opts), to: Sources, as: :search
  defdelegate list(scope, project_id, session_id, opts), to: Catalog
  defdelegate get(scope, project_id, session_id, id), to: Catalog
  defdelegate history(scope, project_id, session_id, id, opts), to: Catalog
  defdelegate propose(scope, project_id, session_id, attrs), to: Commands.Propose, as: :run
  defdelegate revise(scope, project_id, session_id, id, version, attrs), to: Commands.Revise, as: :run
  defdelegate accept(scope, project_id, session_id, id, version, key), to: Commands.Accept, as: :run
end
