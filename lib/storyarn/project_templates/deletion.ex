defmodule Storyarn.ProjectTemplates.Deletion do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker

  def delete_template(%Scope{} = scope, %ProjectTemplate{} = template) do
    Repo.transact(fn ->
      with %ProjectTemplate{} = template <- lock_template(template.id),
           :ok <- Authorization.authorize_template_manager(scope, template),
           :ok <- ensure_archived(template),
           storage_keys = template_storage_keys(template.id),
           {:ok, deleted_template} <- Repo.delete(template),
           {:ok, _job} <- enqueue_artifact_gc(storage_keys) do
        {:ok, deleted_template}
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def perform_template_artifact_gc(storage_keys) when is_list(storage_keys) do
    storage_keys
    |> Enum.filter(&valid_storage_key?/1)
    |> Enum.uniq()
    |> Enum.reduce([], fn key, failures ->
      case SnapshotStorage.delete_snapshot(key) do
        :ok -> failures
        {:error, reason} -> [%{"storage_key" => key, "reason" => inspect(reason)} | failures]
      end
    end)
    |> case do
      [] -> :ok
      failures -> {:error, %{"failed_deletions" => Enum.reverse(failures)}}
    end
  end

  def perform_template_artifact_gc(_storage_keys), do: {:error, :invalid_storage_keys}

  defp lock_template(template_id) do
    ProjectTemplate
    |> where([template], template.id == ^template_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp ensure_archived(%ProjectTemplate{status: "archived"}), do: :ok
  defp ensure_archived(%ProjectTemplate{}), do: {:error, :template_must_be_archived}

  defp template_storage_keys(template_id) do
    (version_storage_keys(template_id) ++ publication_storage_keys(template_id))
    |> List.flatten()
    |> Enum.filter(&valid_storage_key?/1)
    |> Enum.uniq()
  end

  defp version_storage_keys(template_id) do
    Repo.all(
      from version in ProjectTemplateVersion,
        where: version.project_template_id == ^template_id,
        select: [version.snapshot_storage_key, version.asset_manifest_storage_key]
    )
  end

  defp publication_storage_keys(template_id) do
    Repo.all(
      from publication in ProjectTemplatePublication,
        where: publication.project_template_id == ^template_id,
        select: [publication.snapshot_storage_key, publication.asset_manifest_storage_key]
    )
  end

  defp enqueue_artifact_gc([]), do: {:ok, nil}

  defp enqueue_artifact_gc(storage_keys) do
    %{"storage_keys" => storage_keys}
    |> DeleteProjectTemplateArtifactsWorker.new()
    |> Oban.insert()
  end

  defp valid_storage_key?(value), do: is_binary(value) and value != ""
end
