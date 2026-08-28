defmodule Storyarn.Projects.Lifecycle do
  @moduledoc false

  alias Storyarn.Projects.Events
  alias Storyarn.Projects.Lifecycle.Commands.UniqueSlug
  alias Storyarn.Projects.LocalizationLanguageCatalog
  alias Storyarn.Projects.LocalizationReadModel
  alias Storyarn.Projects.LocalizationSettings
  alias Storyarn.Projects.NameNormalizer
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectClassification
  alias Storyarn.Projects.ProjectCrud
  alias Storyarn.Projects.WorkspaceDataLifecycle

  defdelegate list_projects(scope), to: ProjectCrud
  defdelegate list_projects_for_workspace(workspace_id, scope), to: ProjectCrud
  defdelegate get_project(scope, id), to: ProjectCrud
  defdelegate reload_project(scope, id), to: ProjectCrud
  defdelegate get_project!(id), to: ProjectCrud
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: ProjectCrud
  defdelegate create_project(scope, attrs), to: ProjectCrud
  defdelegate lock_and_check_workspace_capacity(workspace_id), to: ProjectCrud
  defdelegate change_project(project, attrs \\ %{}), to: ProjectCrud
  defdelegate change_new_project(), to: ProjectCrud
  defdelegate change_new_project(project, attrs \\ %{}), to: ProjectCrud
  defdelegate update_project(project, attrs), to: ProjectCrud
  defdelegate touch_project(project_id, at \\ nil), to: ProjectCrud
  defdelegate delete_project(project, user_id), to: ProjectCrud
  defdelegate permanently_delete_project(project), to: ProjectCrud
  defdelegate list_deleted_projects(workspace_id), to: ProjectCrud
  defdelegate get_deleted_project(workspace_id, project_id), to: ProjectCrud
  defdelegate auto_versioning_enabled?(project_id, entity_type), to: ProjectCrud

  defdelegate ensure_source_language(project), to: LocalizationSettings
  defdelegate get_source_language(project_id), to: LocalizationReadModel

  defdelegate change_source_language(actor_scope, project, locale_code, opts),
    to: LocalizationSettings

  defdelegate source_language_options(), to: LocalizationLanguageCatalog, as: :options

  defdelegate source_language_option(code, label \\ nil),
    to: LocalizationLanguageCatalog,
    as: :option

  defdelegate project_classification_options(), to: ProjectClassification, as: :project_options

  defdelegate slugify_project_name(name), to: NameNormalizer, as: :slugify
  defdelegate generate_unique_slug(queryable, scope, name), to: UniqueSlug, as: :generate

  def new_project, do: %Project{}
  defdelegate project_theme_colors(project), to: Project, as: :theme_colors

  defdelegate prepare_workspace_data_hard_delete(workspace_id),
    to: WorkspaceDataLifecycle,
    as: :prepare_hard_delete

  defdelegate publish_committed_workspace_data_hard_delete(preparation),
    to: WorkspaceDataLifecycle,
    as: :publish_committed_hard_delete

  defdelegate emit_event(scope_or_user, event_type, payload), to: Events, as: :emit
  defdelegate project_created(scope_or_user, project), to: Events
  defdelegate template_installation_requested(scope, install, template), to: Events
  defdelegate template_installation_finished(scope_or_user, status, payload), to: Events
  defdelegate version_control_settings_updated(scope, project, attrs), to: Events
  defdelegate asset_uploaded(user, payload), to: Events
end
