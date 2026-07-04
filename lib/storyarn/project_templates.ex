defmodule Storyarn.ProjectTemplates do
  @moduledoc """
  Project template publishing and instantiation.

  A template has mutable metadata and points to immutable version artifacts. A
  project created from a template is a normal mutable project and is not kept in
  sync with future template versions.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @type scope :: Scope.t()
  @type attrs :: map()

  @doc """
  Lists templates visible to the current user.
  """
  @spec list_templates(scope(), keyword()) :: [ProjectTemplate.t()]
  def list_templates(%Scope{user: %{id: user_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, "active")

    ProjectTemplate
    |> visible_templates_query(user_id)
    |> where([t], t.status == ^status)
    |> preload([:owner, :source_project, :current_version])
    |> order_by([t], asc: t.visibility, asc: t.name, asc: t.id)
    |> Repo.all()
  end

  @doc """
  Fetches one template visible to the current user.
  """
  @spec get_template!(scope(), integer()) :: ProjectTemplate.t()
  def get_template!(%Scope{user: %{id: user_id}}, id) do
    ProjectTemplate
    |> visible_templates_query(user_id)
    |> where([t], t.id == ^id)
    |> preload([:owner, :source_project, :current_version])
    |> Repo.one!()
  end

  @doc """
  Lists recent installs for a template owned by the current user.
  """
  @spec list_template_installs(scope(), ProjectTemplate.t(), keyword()) :: [ProjectTemplateInstall.t()]
  def list_template_installs(scope, template, opts \\ [])

  def list_template_installs(%Scope{user: %{id: user_id}}, %ProjectTemplate{owner_id: user_id} = template, opts) do
    limit = Keyword.get(opts, :limit, 10)

    ProjectTemplateInstall
    |> join(:inner, [install], version in assoc(install, :project_template_version))
    |> where([_install, version], version.project_template_id == ^template.id)
    |> order_by([install, _version], desc: install.installed_at, desc: install.id)
    |> limit(^limit)
    |> preload([_install, version], [:user, :workspace, :project, project_template_version: version])
    |> Repo.all()
  end

  def list_template_installs(%Scope{}, %ProjectTemplate{}, _opts), do: []

  @doc """
  Creates a private template and publishes its first immutable version.
  """
  @spec create_template_from_project(scope(), Project.t(), attrs()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  def create_template_from_project(%Scope{} = scope, %Project{} = source_project, attrs) do
    with :ok <- ensure_private_visibility(attrs),
         {:ok, source_project} <- authorize_source_project(scope, source_project),
         {:ok, audit_report} <- Audit.run(source_project.id) do
      name = template_name(attrs, source_project)
      slug = NameNormalizer.generate_unique_slug(ProjectTemplate, [owner_id: scope.user.id], name)

      create_template_with_version(scope, source_project, attrs, name, slug, audit_report)
    end
  end

  @doc """
  Publishes a new immutable version for an existing private template.
  """
  @spec publish_new_version(scope(), ProjectTemplate.t(), Project.t()) ::
          {:ok, ProjectTemplate.t()} | {:error, term()}
  def publish_new_version(%Scope{} = scope, %ProjectTemplate{} = template, %Project{} = source_project) do
    with :ok <- authorize_template_owner(scope, template),
         {:ok, source_project} <- authorize_source_project(scope, source_project),
         {:ok, audit_report} <- Audit.run(source_project.id) do
      publish_version_transaction(scope, template, source_project, audit_report)
    end
  end

  @doc """
  Updates mutable metadata for an owned private template.
  """
  @spec update_template(scope(), ProjectTemplate.t(), attrs()) ::
          {:ok, ProjectTemplate.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update_template(%Scope{} = scope, %ProjectTemplate{} = template, attrs) do
    with :ok <- authorize_template_owner(scope, template) do
      template
      |> ProjectTemplate.update_changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, template} -> {:ok, preload_template(template)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Creates a normal mutable project from an immutable template version.
  """
  @spec instantiate_template(scope(), ProjectTemplateVersion.t(), Workspace.t(), attrs()) ::
          {:ok, Project.t()} | {:error, term()}
  def instantiate_template(%Scope{} = scope, %ProjectTemplateVersion{} = version, %Workspace{} = workspace, attrs) do
    version = Repo.preload(version, [:project_template])

    with :ok <- authorize_template_visibility(scope, version.project_template),
         {:ok, workspace, _membership} <- Workspaces.authorize(scope, workspace.id, :create_project),
         :ok <- Billing.can_create_project?(workspace),
         {:ok, snapshot} <- SnapshotStorage.load_snapshot(version.snapshot_storage_key),
         {:ok, project} <-
           Versioning.recover_project(workspace.id, snapshot, scope.user.id,
             name: install_name(attrs, version),
             template_clone: true
           ),
         {:ok, project} <- mark_template_origin(project, version),
         {:ok, _install} <- record_install(scope, version, workspace, project) do
      {:ok, project}
    end
  end

  defp visible_templates_query(query, user_id) do
    from t in query,
      where:
        (t.visibility == "private" and t.owner_id == ^user_id) or
          t.visibility == "public"
  end

  defp create_template_with_version(scope, source_project, attrs, name, slug, audit_report) do
    Repo.transact(fn ->
      do_create_template_with_version(scope, source_project, attrs, name, slug, audit_report)
    end)
  end

  defp do_create_template_with_version(scope, source_project, attrs, name, slug, audit_report) do
    with {:ok, template} <- insert_template(scope, source_project, attrs, name, slug),
         {:ok, version} <- create_version(scope, template, source_project, 1, audit_report),
         {:ok, template} <- set_current_version(template, version) do
      {:ok, preload_template(template)}
    end
  end

  defp publish_version_transaction(scope, template, source_project, audit_report) do
    Repo.transact(fn ->
      do_publish_version(scope, template, source_project, audit_report)
    end)
  end

  defp do_publish_version(scope, template, source_project, audit_report) do
    next_version = next_version_number(template.id)

    with {:ok, version} <- create_version(scope, template, source_project, next_version, audit_report),
         {:ok, template} <- set_current_version(template, version) do
      {:ok, preload_template(template)}
    end
  end

  defp preload_template(template) do
    Repo.preload(template, [:owner, :source_project, :current_version], force: true)
  end

  defp ensure_private_visibility(attrs) do
    visibility = Map.get(attrs, :visibility) || Map.get(attrs, "visibility") || "private"

    if visibility == "private" do
      :ok
    else
      {:error, :public_visibility_requires_admin}
    end
  end

  defp authorize_source_project(%Scope{user: user} = scope, %Project{id: project_id}) when not is_nil(user) do
    case Projects.get_project(scope, project_id) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) do
          {:ok, project}
        else
          {:error, :unauthorized}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authorize_source_project(_scope, _project), do: {:error, :unauthorized}

  defp authorize_template_owner(%Scope{user: %{id: user_id}}, %ProjectTemplate{owner_id: user_id, visibility: "private"}) do
    :ok
  end

  defp authorize_template_owner(_scope, _template), do: {:error, :unauthorized}

  defp authorize_template_visibility(%Scope{user: %{id: user_id}}, %ProjectTemplate{
         visibility: "private",
         owner_id: user_id
       }) do
    :ok
  end

  defp authorize_template_visibility(%Scope{user: %{}}, %ProjectTemplate{visibility: "public"}) do
    :ok
  end

  defp authorize_template_visibility(_scope, _template), do: {:error, :unauthorized}

  defp insert_template(scope, source_project, attrs, name, slug) do
    %ProjectTemplate{owner_id: scope.user.id, source_project_id: source_project.id}
    |> ProjectTemplate.create_changeset(%{
      name: name,
      slug: slug,
      description: Map.get(attrs, :description) || Map.get(attrs, "description") || source_project.description,
      visibility: "private",
      status: "active"
    })
    |> Repo.insert()
  end

  defp create_version(scope, template, source_project, version_number, audit_report) do
    snapshot = ProjectSnapshotBuilder.build_snapshot(source_project.id)
    asset_manifest = build_asset_manifest(source_project.id)
    checksum = checksum(%{"snapshot" => snapshot, "asset_manifest" => asset_manifest})

    with {:ok, snapshot_key} <- store_artifact(template, version_number, "snapshot", snapshot),
         {:ok, asset_manifest_key} <- store_artifact(template, version_number, "asset-manifest", asset_manifest) do
      now = TimeHelpers.now()

      %ProjectTemplateVersion{
        project_template_id: template.id,
        source_project_id: source_project.id,
        published_by_id: scope.user.id
      }
      |> ProjectTemplateVersion.create_changeset(%{
        version_number: version_number,
        snapshot_storage_key: snapshot_key,
        asset_manifest_storage_key: asset_manifest_key,
        checksum: checksum,
        entity_counts: Map.get(snapshot, "entity_counts", %{}),
        audit_report: audit_report,
        published_at: now
      })
      |> Repo.insert()
    end
  end

  defp store_artifact(template, version_number, name, data) do
    suffix = SnapshotStorage.unique_key_suffix()
    key = "project_templates/#{template.id}/versions/#{version_number}/#{name}-#{suffix}.json.gz"

    case SnapshotStorage.store_raw(key, data) do
      {:ok, _size_bytes} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_asset_manifest(project_id) do
    assets =
      project_id
      |> Assets.list_assets_for_export()
      |> Enum.map(fn asset ->
        %{
          "id" => asset.id,
          "filename" => asset.filename,
          "content_type" => asset.content_type,
          "size" => asset.size,
          "key" => asset.key,
          "url" => asset.url,
          "blob_hash" => asset.blob_hash,
          "metadata" => asset.metadata || %{}
        }
      end)

    %{
      "format_version" => 1,
      "assets" => assets,
      "asset_count" => length(assets)
    }
  end

  defp checksum(data) do
    data
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp set_current_version(template, version) do
    template
    |> ProjectTemplate.current_version_changeset(version.id)
    |> Repo.update()
  end

  defp next_version_number(template_id) do
    ProjectTemplateVersion
    |> where([v], v.project_template_id == ^template_id)
    |> select([v], coalesce(max(v.version_number), 0) + 1)
    |> Repo.one()
  end

  defp mark_template_origin(project, version) do
    project
    |> Ecto.Changeset.change(created_from_template_version_id: version.id)
    |> Repo.update()
  end

  defp record_install(scope, version, workspace, project) do
    %ProjectTemplateInstall{
      project_template_version_id: version.id,
      user_id: scope.user.id,
      workspace_id: workspace.id,
      project_id: project.id
    }
    |> ProjectTemplateInstall.create_changeset(%{installed_at: TimeHelpers.now()})
    |> Repo.insert()
  end

  defp template_name(attrs, source_project) do
    Map.get(attrs, :name) || Map.get(attrs, "name") || source_project.name
  end

  defp install_name(attrs, version) do
    Map.get(attrs, :name) ||
      Map.get(attrs, "name") ||
      version.project_template.name
  end
end
