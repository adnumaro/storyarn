defmodule Storyarn.Sheets.Access do
  @moduledoc """
  Public capability boundary for Sheet-specific project access.

  It authorizes projects through consumer-local membership projections so the
  Sheets bounded context does not depend on Projects or Workspaces internals.
  """

  alias Storyarn.Sheets.Access.Queries.Projects

  defdelegate get_project(scope, project_id), to: Projects
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Projects
end
