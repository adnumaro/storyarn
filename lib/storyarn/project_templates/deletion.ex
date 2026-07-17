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
    Repo.transact(
      fn ->
        with %ProjectTemplate{} = template <- lock_template(template.id),
             :ok <- Authorization.authorize_template_manager(scope, template),
             :ok <- ensure_archived(template),
             {:ok, storage_keys} <- template_storage_keys(template.id),
             {:ok, deleted_template} <- Repo.delete(template),
             {:ok, _job} <- enqueue_artifact_gc(storage_keys) do
          {:ok, deleted_template}
        else
          nil -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
      end,
      # Reading imported manifests performs storage I/O while the template row
      # is locked. Do not let a DBConnection timeout release that lock while
      # the deletion workflow is still deciding which artifacts to enqueue.
      timeout: :infinity
    )
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
    version_keys = version_storage_keys(template_id)
    publication_keys = publication_storage_keys(template_id)

    with {:ok, imported_blob_keys} <- imported_blob_storage_keys(version_keys) do
      storage_keys =
        (version_keys ++ publication_keys ++ imported_blob_keys)
        |> List.flatten()
        |> Enum.filter(&valid_storage_key?/1)
        |> Enum.uniq()

      {:ok, storage_keys}
    end
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

  defp imported_blob_storage_keys(version_keys) do
    version_keys
    |> Enum.map(&List.last/1)
    |> Enum.filter(&portable_import_manifest_key?/1)
    |> Enum.reduce_while({:ok, []}, fn manifest_key, {:ok, keys} ->
      case load_imported_blob_keys(manifest_key) do
        {:ok, imported_keys} -> {:cont, {:ok, imported_keys ++ keys}}
        {:error, reason} -> {:halt, {:error, {:template_asset_manifest_unreadable, manifest_key, reason}}}
      end
    end)
  end

  defp load_imported_blob_keys(manifest_key) do
    expected_prefix = imported_blob_prefix(manifest_key)

    case SnapshotStorage.load_snapshot(manifest_key) do
      {:ok, %{"assets" => assets}} when is_list(assets) ->
        keys =
          assets
          |> Enum.map(fn
            %{"key" => key} when is_binary(key) -> key
            _asset -> nil
          end)
          |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, expected_prefix)))

        {:ok, keys}

      {:ok, _invalid_manifest} ->
        {:error, :invalid_asset_manifest}

      {:error, _reason} = error ->
        error
    end
  end

  defp portable_import_manifest_key?(storage_key) when is_binary(storage_key) do
    match?(
      ["project_templates", "imports", slug, suffix, "asset-manifest.json.gz"]
      when slug != "" and suffix != "",
      String.split(storage_key, "/")
    )
  end

  defp portable_import_manifest_key?(_storage_key), do: false

  defp imported_blob_prefix(manifest_key) do
    ["project_templates", "imports", slug, suffix, "asset-manifest.json.gz"] =
      String.split(manifest_key, "/")

    "project_templates/imported_blobs/#{slug}/#{suffix}/"
  end

  defp enqueue_artifact_gc([]), do: {:ok, nil}

  defp enqueue_artifact_gc(storage_keys) do
    %{"storage_keys" => storage_keys}
    |> DeleteProjectTemplateArtifactsWorker.new()
    |> Oban.insert()
  end

  defp valid_storage_key?(value), do: is_binary(value) and value != ""
end
