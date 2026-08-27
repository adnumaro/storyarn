defmodule Storyarn.Localization.ProjectAccess do
  @moduledoc false

  alias Storyarn.Localization.ProjectAccess.Commands.ProjectReferenceIntegrity
  alias Storyarn.Localization.ProjectAccess.Queries.Projects

  defdelegate get_project(actor_scope, project_id), to: Projects
  defdelegate get_project_by_slugs(actor_scope, workspace_slug, project_slug), to: Projects
  defdelegate get_effective_membership(project_id, user_id, workspace_id), to: Projects

  defdelegate lock_active_project(project_id, lock_mode \\ :share),
    to: ProjectReferenceIntegrity

  defdelegate lock_active_references(project_id, specs), to: ProjectReferenceIntegrity

  defdelegate ensure_locked_asset_content_type(project_id, asset_id, context, pattern),
    to: ProjectReferenceIntegrity

  defdelegate normalize_optional_id(value), to: ProjectReferenceIntegrity
end
