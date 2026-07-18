defmodule Storyarn.ProjectTemplates do
  @moduledoc """
  Project template publishing and instantiation.

  A template has mutable metadata and points to immutable version artifacts. A
  project created from a template is a normal mutable project and is not kept in
  sync with future template versions.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.Deletion
  alias Storyarn.ProjectTemplates.Installation
  alias Storyarn.ProjectTemplates.PortableExport
  alias Storyarn.ProjectTemplates.PortableImport
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.ProjectTemplates.PublicationRunner
  alias Storyarn.ProjectTemplates.TemplateQueries
  alias Storyarn.Workspaces.Workspace

  @type scope :: Scope.t()
  @type attrs :: map()

  @doc """
  Lists templates visible to the current user.
  """
  @spec list_templates(scope(), keyword()) :: [ProjectTemplate.t()]
  defdelegate list_templates(scope, opts \\ []), to: TemplateQueries

  @doc """
  Returns a paginated page of templates visible to the current user.
  """
  @spec paginate_templates(scope(), keyword()) :: map()
  defdelegate paginate_templates(scope, opts \\ []), to: TemplateQueries

  @doc """
  Fetches one template visible to the current user.
  """
  @spec get_template(scope(), integer(), keyword()) :: {:ok, ProjectTemplate.t()} | {:error, :not_found}
  defdelegate get_template(scope, id, opts \\ []), to: TemplateQueries

  @doc """
  Fetches one template visible to the current user, raising when not found.
  """
  @spec get_template!(scope(), integer()) :: ProjectTemplate.t()
  defdelegate get_template!(scope, id), to: TemplateQueries

  @doc """
  Lists immutable versions for a template visible to the current user.
  """
  @spec list_template_versions(scope(), ProjectTemplate.t()) :: [ProjectTemplateVersion.t()]
  defdelegate list_template_versions(scope, template), to: TemplateQueries

  @doc """
  Lists recent installs for a template owned by the current user.
  """
  @spec list_template_installs(scope(), ProjectTemplate.t(), keyword()) :: [ProjectTemplateInstall.t()]
  defdelegate list_template_installs(scope, template, opts \\ []), to: TemplateQueries

  @doc """
  Lists template publication attempts visible to the current user.
  """
  @spec list_template_publications(scope(), keyword()) :: [ProjectTemplatePublication.t()]
  defdelegate list_template_publications(scope, opts \\ []), to: TemplateQueries

  @doc """
  Returns true when the current user can manage the private template metadata.
  """
  @spec can_manage_template?(scope(), ProjectTemplate.t()) :: boolean()
  defdelegate can_manage_template?(scope, template), to: Authorization

  @doc """
  Returns true when the current user can publish a template from the source project.
  """
  @spec can_publish_source_project?(scope(), Project.t()) :: boolean()
  defdelegate can_publish_source_project?(scope, project), to: Authorization

  @doc """
  Fetches one template publication visible to the current user.
  """
  @spec get_template_publication!(scope(), integer()) :: ProjectTemplatePublication.t()
  defdelegate get_template_publication!(scope, id), to: TemplateQueries

  @doc """
  Requests asynchronous publication of a new private template.
  """
  @spec request_template_publication(scope(), Project.t(), attrs()) ::
          {:ok, ProjectTemplatePublication.t()} | {:error, term()}
  defdelegate request_template_publication(scope, source_project, attrs), to: PublicationRunner

  @doc """
  Requests asynchronous publication of a new version for an existing private template.
  """
  @spec request_template_version_publication(scope(), ProjectTemplate.t(), Project.t(), attrs()) ::
          {:ok, ProjectTemplatePublication.t()} | {:error, term()}
  defdelegate request_template_version_publication(scope, template, source_project, attrs), to: PublicationRunner

  @doc """
  Runs a queued template publication. Intended for Oban workers.
  """
  @spec perform_template_publication(integer(), keyword()) ::
          {:ok, ProjectTemplatePublication.t()} | {:error, term()}
  defdelegate perform_template_publication(publication_id, opts \\ []), to: PublicationRunner

  @doc """
  Subscribes the caller to template publication changes for a project or template.
  """
  @spec subscribe_template_publications(Project.t() | ProjectTemplate.t()) :: :ok | {:error, term()}
  defdelegate subscribe_template_publications(project_or_template), to: PublicationRunner

  @doc """
  Creates a private template and publishes its first immutable version.

  Production UI uses `request_template_publication/3`. This synchronous helper
  exists for tests, fixtures, scripts and other controlled internal workflows,
  and executes the same publication runner used by Oban.
  """
  @spec create_template_from_project(scope(), Project.t(), attrs()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  defdelegate create_template_from_project(scope, source_project, attrs), to: PublicationRunner

  @doc """
  Publishes a new immutable version for an existing private template.

  Production UI uses `request_template_version_publication/4`.
  """
  @spec publish_new_version(scope(), ProjectTemplate.t(), Project.t()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  defdelegate publish_new_version(scope, template, source_project), to: PublicationRunner

  @doc """
  Updates mutable metadata for an owned private template.
  """
  @spec update_template(scope(), ProjectTemplate.t(), attrs()) ::
          {:ok, ProjectTemplate.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate update_template(scope, template, attrs), to: PublicationRunner

  @doc """
  Archives a manageable private template.
  """
  @spec archive_template(scope(), ProjectTemplate.t()) ::
          {:ok, ProjectTemplate.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate archive_template(scope, template), to: PublicationRunner

  @doc """
  Restores a manageable archived private template.
  """
  @spec unarchive_template(scope(), ProjectTemplate.t()) ::
          {:ok, ProjectTemplate.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defdelegate unarchive_template(scope, template), to: PublicationRunner

  @doc """
  Permanently deletes an archived manageable private template and enqueues storage artifact GC.
  """
  @spec delete_template(scope(), ProjectTemplate.t()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  defdelegate delete_template(scope, template), to: Deletion

  @doc """
  Deletes template storage artifacts. Intended for Oban workers.
  """
  @spec perform_template_artifact_gc([String.t()]) :: :ok | {:error, term()}
  defdelegate perform_template_artifact_gc(storage_keys), to: Deletion

  @doc """
  Atomically updates template metadata and publishes a new immutable version.

  Production UI uses `request_template_version_publication/4`.
  """
  @spec update_template_and_publish_new_version(scope(), ProjectTemplate.t(), Project.t(), attrs()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  defdelegate update_template_and_publish_new_version(scope, template, source_project, attrs), to: PublicationRunner

  @doc """
  Creates a normal mutable project from an immutable template version.
  """
  @spec instantiate_template(scope(), ProjectTemplateVersion.t(), Workspace.t(), attrs()) ::
          {:ok, Project.t()} | {:error, term()}
  defdelegate instantiate_template(scope, version, workspace, attrs), to: Installation

  @doc """
  Requests asynchronous creation of a project from an immutable template version.
  """
  @spec request_template_instantiation(scope(), ProjectTemplateVersion.t(), Workspace.t(), attrs()) ::
          {:ok, ProjectTemplateInstall.t()} | {:error, term()}
  defdelegate request_template_instantiation(scope, version, workspace, attrs), to: Installation

  @doc """
  Runs a queued template installation. Intended for Oban workers.
  """
  @spec perform_template_installation(integer(), keyword()) ::
          {:ok, ProjectTemplateInstall.t()} | {:error, term()}
  defdelegate perform_template_installation(installation_id, opts \\ []), to: Installation

  @spec list_active_workspace_installations(scope(), Workspace.t()) :: [ProjectTemplateInstall.t()]
  defdelegate list_active_workspace_installations(scope, workspace), to: Installation

  @doc """
  Lists the current user's failed installations that still need acknowledgement.
  """
  @spec list_pending_workspace_installation_failures(scope(), Workspace.t()) :: [ProjectTemplateInstall.t()]
  defdelegate list_pending_workspace_installation_failures(scope, workspace), to: Installation

  @doc """
  Lists the current user's pending failed installations for one template.
  """
  @spec list_pending_template_installation_failures(scope(), ProjectTemplate.t()) ::
          [ProjectTemplateInstall.t()]
  defdelegate list_pending_template_installation_failures(scope, template), to: Installation

  @doc """
  Returns whether one failed installation still needs acknowledgement by the current user.
  """
  @spec pending_installation_failure?(scope(), Workspace.t(), integer()) :: boolean()
  defdelegate pending_installation_failure?(scope, workspace, installation_id), to: Installation

  @doc """
  Dismisses one failed installation notification for the current user.
  """
  @spec dismiss_installation_failure(scope(), Workspace.t(), integer()) ::
          {:ok, ProjectTemplateInstall.t()}
          | {:error, :not_found | :unauthorized | Ecto.Changeset.t()}
  defdelegate dismiss_installation_failure(scope, workspace, installation_id), to: Installation

  @spec list_active_template_installations(scope(), ProjectTemplate.t()) :: [ProjectTemplateInstall.t()]
  defdelegate list_active_template_installations(scope, template), to: Installation

  defdelegate subscribe_workspace_installations(workspace), to: Installation
  defdelegate subscribe_user_installations(scope), to: Installation

  @doc """
  Exports an audited project template bundle that can be imported into another Storyarn deployment.
  """
  @spec export_portable_template(pos_integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate export_portable_template(project_id, output_path, opts \\ []), to: PortableExport, as: :export_project

  @doc """
  Reads a portable template bundle manifest without importing it.
  """
  @spec preview_portable_template(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate preview_portable_template(path, opts \\ []), to: PortableImport, as: :preview_bundle

  @doc """
  Imports a portable template bundle into this deployment.
  """
  @spec import_portable_template(String.t(), keyword()) :: {:ok, ProjectTemplate.t()} | {:error, term()}
  defdelegate import_portable_template(path, opts \\ []), to: PortableImport, as: :import_bundle
end
