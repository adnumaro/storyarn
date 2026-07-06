defmodule Storyarn.ProjectTemplates.Installation do
  @moduledoc false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @spec instantiate_template(Scope.t(), ProjectTemplateVersion.t(), Workspace.t(), map()) ::
          {:ok, Project.t()} | {:error, term()}
  def instantiate_template(%Scope{} = scope, %ProjectTemplateVersion{} = version, %Workspace{} = workspace, attrs) do
    version = Repo.preload(version, [:project_template])

    with :ok <- Authorization.authorize_template_visibility(scope, version.project_template),
         {:ok, workspace, _membership} <- Workspaces.authorize(scope, workspace.id, :create_project),
         :ok <- Billing.can_create_project?(workspace),
         {:ok, snapshot} <- load_verified_template_snapshot(version) do
      instantiate_template_transaction(scope, version, workspace, attrs, snapshot)
    end
  end

  defp load_verified_template_snapshot(version) do
    with {:ok, snapshot} <- SnapshotStorage.load_snapshot(version.snapshot_storage_key),
         {:ok, asset_manifest} <- load_template_asset_manifest(version),
         :ok <- verify_template_checksum(version, snapshot, asset_manifest) do
      {:ok, snapshot}
    end
  end

  defp load_template_asset_manifest(%ProjectTemplateVersion{asset_manifest_storage_key: nil}) do
    {:error, :missing_asset_manifest}
  end

  defp load_template_asset_manifest(version) do
    SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)
  end

  defp verify_template_checksum(%ProjectTemplateVersion{checksum: nil}, _snapshot, _asset_manifest) do
    {:error, :missing_checksum}
  end

  defp verify_template_checksum(version, snapshot, asset_manifest) do
    data = %{"snapshot" => snapshot, "asset_manifest" => asset_manifest}

    if version.checksum == Artifact.checksum(data) do
      :ok
    else
      {:error, :checksum_mismatch}
    end
  end

  defp instantiate_template_transaction(scope, version, workspace, attrs, snapshot) do
    Repo.transaction(
      fn ->
        case do_instantiate_template(scope, version, workspace, attrs, snapshot) do
          {:ok, project} -> project
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: to_timeout(minute: 5)
    )
  end

  defp do_instantiate_template(scope, version, workspace, attrs, snapshot) do
    with {:ok, project} <-
           Versioning.recover_project(workspace.id, snapshot, scope.user.id,
             name: install_name(attrs, version),
             template_clone: true
           ),
         {:ok, project} <- mark_template_origin(project, version),
         {:ok, _install} <- record_install(scope, version, workspace, project) do
      {:ok, project}
    end
  end

  defp mark_template_origin(project, version) do
    project
    |> Ecto.Changeset.change(created_from_template_version_id: version.id)
    |> Ecto.Changeset.foreign_key_constraint(:created_from_template_version_id)
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

  defp install_name(attrs, version) do
    Map.get(attrs, :name) ||
      Map.get(attrs, "name") ||
      version.project_template.name
  end
end
