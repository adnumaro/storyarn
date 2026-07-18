defmodule Storyarn.ProjectTemplates.Deletion do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker

  @deletion_transaction_timeout to_timeout(second: 30)
  @manifest_load_event [:storyarn, :project_templates, :deletion, :asset_manifest_load]

  def delete_template(%Scope{} = scope, %ProjectTemplate{} = template) do
    with {:ok, prepared} <- prepare_template_deletion(scope, template.id) do
      commit_template_deletion(scope, template.id, prepared)
    end
  end

  defp prepare_template_deletion(scope, template_id) do
    with %ProjectTemplate{} = template <- Repo.get(ProjectTemplate, template_id),
         :ok <- Authorization.authorize_template_manager(scope, template),
         :ok <- ensure_archived(template),
         artifact_ownership = template_artifact_ownership(template_id),
         {:ok, storage_keys} <- template_storage_keys(artifact_ownership) do
      {:ok, %{artifact_ownership: artifact_ownership, storage_keys: storage_keys}}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp commit_template_deletion(scope, template_id, prepared) do
    Repo.transact(
      fn ->
        with %ProjectTemplate{} = template <- lock_template(template_id),
             :ok <- Authorization.authorize_template_manager(scope, template),
             :ok <- ensure_archived(template),
             :ok <-
               ensure_artifact_ownership_unchanged(
                 template_id,
                 prepared.artifact_ownership
               ),
             {:ok, deleted_template} <- Repo.delete(template),
             {:ok, _job} <- enqueue_artifact_gc(prepared.storage_keys) do
          {:ok, deleted_template}
        else
          nil -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
      end,
      # All remote manifest reads happen during preparation. This bounded
      # transaction only locks and revalidates database ownership before the
      # template delete and durable GC enqueue commit atomically.
      timeout: @deletion_transaction_timeout
    )
  end

  def perform_template_artifact_gc(storage_keys) when is_list(storage_keys) do
    with {:ok, storage_keys} <- validate_template_storage_keys(storage_keys) do
      delete_template_storage_keys(storage_keys)
    end
  end

  def perform_template_artifact_gc(_storage_keys), do: {:error, :invalid_storage_keys}

  defp delete_template_storage_keys(storage_keys) do
    storage_keys
    |> Enum.reduce([], &collect_storage_deletion_failure/2)
    |> deletion_result()
  end

  defp collect_storage_deletion_failure(key, failures) do
    case StorageCompensation.delete_or_enqueue(key) do
      :ok -> failures
      {:error, reason} -> [%{"storage_key" => key, "reason" => inspect(reason)} | failures]
    end
  end

  defp deletion_result([]), do: :ok

  defp deletion_result(failures), do: {:error, %{"failed_deletions" => Enum.reverse(failures)}}

  defp lock_template(template_id) do
    ProjectTemplate
    |> where([template], template.id == ^template_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp ensure_archived(%ProjectTemplate{status: "archived"}), do: :ok
  defp ensure_archived(%ProjectTemplate{}), do: {:error, :template_must_be_archived}

  defp template_storage_keys(artifact_ownership) do
    version_keys = artifact_storage_keys(artifact_ownership, "version")
    publication_keys = artifact_storage_keys(artifact_ownership, "publication")

    with {:ok, imported_blob_keys} <- imported_blob_storage_keys(version_keys) do
      version_keys
      |> Kernel.++(publication_keys)
      |> Kernel.++(imported_blob_keys)
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> validate_template_storage_keys()
    end
  end

  defp ensure_artifact_ownership_unchanged(template_id, expected_ownership) do
    current_ownership = lock_template_artifact_ownership(template_id)

    if current_ownership == expected_ownership,
      do: :ok,
      else: {:error, :template_changed_during_deletion}
  end

  defp validate_template_storage_keys(storage_keys) do
    storage_keys = Enum.uniq(storage_keys)

    case Enum.reject(storage_keys, &StorageCompensation.template_storage_key?/1) do
      [] ->
        {:ok, storage_keys}

      invalid_keys ->
        {:error,
         {:invalid_template_storage_keys,
          Enum.map(invalid_keys, fn key ->
            if is_binary(key), do: key, else: inspect(key)
          end)}}
    end
  end

  defp template_artifact_ownership(template_id) do
    template_id
    |> artifact_ownership_queries()
    |> Enum.flat_map(&Repo.all/1)
    |> sort_artifact_ownership()
  end

  defp lock_template_artifact_ownership(template_id) do
    template_id
    |> artifact_ownership_queries()
    |> Enum.flat_map(fn query ->
      query
      |> lock("FOR UPDATE")
      |> Repo.all()
    end)
    |> sort_artifact_ownership()
  end

  defp artifact_ownership_queries(template_id) do
    [
      from(version in ProjectTemplateVersion,
        where: version.project_template_id == ^template_id,
        select: %{
          record_type: "version",
          record_id: version.id,
          snapshot_storage_key: version.snapshot_storage_key,
          asset_manifest_storage_key: version.asset_manifest_storage_key
        }
      ),
      from(publication in ProjectTemplatePublication,
        where: publication.project_template_id == ^template_id,
        select: %{
          record_type: "publication",
          record_id: publication.id,
          snapshot_storage_key: publication.snapshot_storage_key,
          asset_manifest_storage_key: publication.asset_manifest_storage_key
        }
      )
    ]
  end

  defp sort_artifact_ownership(ownership), do: Enum.sort_by(ownership, &{&1.record_type, &1.record_id})

  defp artifact_storage_keys(artifact_ownership, record_type) do
    artifact_ownership
    |> Enum.filter(&(&1.record_type == record_type))
    |> Enum.map(&[&1.snapshot_storage_key, &1.asset_manifest_storage_key])
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
    {:ok, expected_identity} = imported_blob_identity(manifest_key)

    :telemetry.execute(@manifest_load_event, %{count: 1}, %{storage_key: manifest_key})

    case SnapshotStorage.load_snapshot(manifest_key) do
      {:ok, %{"assets" => assets}} when is_list(assets) ->
        validate_imported_blob_keys(assets, expected_identity)

      {:ok, _invalid_manifest} ->
        {:error, :invalid_asset_manifest}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_imported_blob_keys(assets, expected_identity) do
    assets
    |> Enum.reduce_while({:ok, []}, fn
      %{"key" => key}, {:ok, keys} when is_binary(key) ->
        if canonical_imported_blob_key?(key, expected_identity) do
          {:cont, {:ok, [key | keys]}}
        else
          {:halt, {:error, :invalid_asset_manifest}}
        end

      _invalid_asset, _keys ->
        {:halt, {:error, :invalid_asset_manifest}}
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      {:error, _reason} = error -> error
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

  defp imported_blob_identity(manifest_key) do
    ["project_templates", "imports", slug, suffix, "asset-manifest.json.gz"] =
      String.split(manifest_key, "/")

    {:ok, {slug, suffix}}
  end

  defp canonical_imported_blob_key?(storage_key, {expected_slug, expected_suffix}) when is_binary(storage_key) do
    case String.split(storage_key, "/") do
      ["project_templates", "imported_blobs", ^expected_slug, ^expected_suffix, hash, filename]
      when filename not in ["", ".", ".."] ->
        String.match?(hash, ~r/\A[0-9a-f]{64}\z/)

      _parts ->
        false
    end
  end

  defp canonical_imported_blob_key?(_storage_key, _expected_identity), do: false

  defp enqueue_artifact_gc([]), do: {:ok, nil}

  defp enqueue_artifact_gc(storage_keys) do
    %{"storage_keys" => storage_keys}
    |> DeleteProjectTemplateArtifactsWorker.new()
    |> Oban.insert()
  end
end
