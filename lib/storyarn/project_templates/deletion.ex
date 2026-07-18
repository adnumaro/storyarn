defmodule Storyarn.ProjectTemplates.Deletion do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker

  @portable_manifest_prefix "project_templates/imports/"
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @internal_artifact_key_regex ~r/\Aproject_template_publications\/([1-9][0-9]*)\/(snapshot|asset-manifest)-[0-9a-f]{16}\.json\.gz\z/
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
         {:ok, storage_keys} <- template_storage_keys(template_id, artifact_ownership) do
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
      referenced_keys = referenced_template_artifact_keys(storage_keys)

      storage_keys
      |> unreferenced_gc_keys(referenced_keys)
      |> delete_template_storage_keys()
    end
  end

  def perform_template_artifact_gc(_storage_keys), do: {:error, :invalid_storage_keys}

  defp referenced_template_artifact_keys(storage_keys) do
    reference_keys =
      storage_keys
      |> Enum.flat_map(&gc_reference_keys/1)
      |> Enum.uniq()

    if reference_keys == [] do
      MapSet.new()
    else
      version_keys =
        Repo.all(
          from version in ProjectTemplateVersion,
            where:
              version.snapshot_storage_key in ^reference_keys or
                version.asset_manifest_storage_key in ^reference_keys,
            select: [version.snapshot_storage_key, version.asset_manifest_storage_key]
        )

      publication_keys =
        Repo.all(
          from publication in ProjectTemplatePublication,
            where:
              publication.snapshot_storage_key in ^reference_keys or
                publication.asset_manifest_storage_key in ^reference_keys,
            select: [
              publication.snapshot_storage_key,
              publication.asset_manifest_storage_key
            ]
        )

      (version_keys ++ publication_keys)
      |> List.flatten()
      |> Enum.filter(&(&1 in reference_keys))
      |> MapSet.new()
    end
  end

  defp unreferenced_gc_keys(storage_keys, referenced_keys) do
    Enum.reject(storage_keys, fn key ->
      key
      |> gc_reference_keys()
      |> Enum.any?(&MapSet.member?(referenced_keys, &1))
    end)
  end

  defp gc_reference_keys(key) do
    case portable_gc_namespace(key) do
      {:ok, slug, suffix} ->
        [
          "project_templates/imports/#{slug}/#{suffix}/snapshot.json.gz",
          "project_templates/imports/#{slug}/#{suffix}/asset-manifest.json.gz"
        ]

      :error ->
        [key]
    end
  end

  defp portable_gc_namespace(key) do
    case String.split(key, "/", trim: false) do
      ["project_templates", namespace, slug, suffix | _rest]
      when namespace in ["imports", "imported_blobs"] and slug != "" and suffix != "" ->
        {:ok, slug, suffix}

      _segments ->
        :error
    end
  end

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

  defp template_storage_keys(template_id, artifact_ownership) do
    artifact_refs =
      Enum.filter(artifact_ownership, fn artifact ->
        not is_nil(artifact.snapshot_storage_key) or
          not is_nil(artifact.asset_manifest_storage_key)
      end)

    with {:ok, artifact_groups} <- validate_artifact_groups(artifact_refs) do
      externally_referenced_keys =
        externally_referenced_artifact_keys(template_id, artifact_groups)

      {:ok, unreferenced_storage_keys(artifact_groups, externally_referenced_keys)}
    end
  end

  defp validate_artifact_groups(artifact_refs) do
    artifact_refs
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn artifact, {:ok, groups} ->
      case validate_artifact_group(artifact) do
        {:ok, group} ->
          {:cont, {:ok, [group | groups]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, groups} -> {:ok, Enum.reverse(groups)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_artifact_group(artifact) do
    if portable_manifest_key?(artifact.asset_manifest_storage_key) do
      validate_portable_artifact_group(artifact)
    else
      validate_internal_artifact_group(artifact)
    end
  end

  defp validate_portable_artifact_group(artifact) do
    case portable_blob_storage_keys_from_artifact(artifact) do
      {:ok, blob_keys} ->
        {:ok,
         %{
           kind: :portable,
           snapshot_key: artifact.snapshot_storage_key,
           manifest_key: artifact.asset_manifest_storage_key,
           blob_keys: blob_keys
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_internal_artifact_group(artifact) do
    snapshot_key = artifact.snapshot_storage_key
    manifest_key = artifact.asset_manifest_storage_key

    with {:ok, publication_id} <- validate_internal_artifact_key(snapshot_key, "snapshot"),
         {:ok, ^publication_id} <-
           validate_internal_artifact_key(manifest_key, "asset-manifest") do
      {:ok,
       %{
         kind: :internal,
         snapshot_key: snapshot_key,
         manifest_key: manifest_key,
         blob_keys: []
       }}
    else
      {:ok, _different_publication_id} ->
        {:error, {:invalid_internal_artifact_pair, snapshot_key, manifest_key}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_internal_artifact_key(key, expected_artifact_name) when is_binary(key) do
    case Regex.run(@internal_artifact_key_regex, key, capture: :all_but_first) do
      [publication_id, ^expected_artifact_name] ->
        if Storage.canonical_key?(key) do
          {:ok, String.to_integer(publication_id)}
        else
          {:error, {:invalid_artifact_storage_key, key}}
        end

      _invalid ->
        {:error, {:invalid_artifact_storage_key, key}}
    end
  end

  defp validate_internal_artifact_key(key, _expected_artifact_name), do: {:error, {:invalid_artifact_storage_key, key}}

  defp externally_referenced_artifact_keys(template_id, artifact_groups) do
    artifact_keys =
      artifact_groups
      |> Enum.flat_map(&[&1.snapshot_key, &1.manifest_key])
      |> Enum.uniq()

    if artifact_keys == [] do
      MapSet.new()
    else
      version_keys =
        Repo.all(
          from version in ProjectTemplateVersion,
            where:
              version.project_template_id != ^template_id and
                (version.snapshot_storage_key in ^artifact_keys or
                   version.asset_manifest_storage_key in ^artifact_keys),
            select: [version.snapshot_storage_key, version.asset_manifest_storage_key]
        )

      publication_keys =
        Repo.all(
          from publication in ProjectTemplatePublication,
            where:
              (is_nil(publication.project_template_id) or
                 publication.project_template_id != ^template_id) and
                (publication.snapshot_storage_key in ^artifact_keys or
                   publication.asset_manifest_storage_key in ^artifact_keys),
            select: [
              publication.snapshot_storage_key,
              publication.asset_manifest_storage_key
            ]
        )

      (version_keys ++ publication_keys)
      |> List.flatten()
      |> Enum.filter(&(&1 in artifact_keys))
      |> MapSet.new()
    end
  end

  defp unreferenced_storage_keys(artifact_groups, externally_referenced_keys) do
    artifact_groups
    |> Enum.flat_map(fn
      %{kind: :portable} = group ->
        artifact_keys = [group.snapshot_key, group.manifest_key]

        if Enum.any?(artifact_keys, &MapSet.member?(externally_referenced_keys, &1)) do
          []
        else
          artifact_keys ++ group.blob_keys
        end

      %{kind: :internal} = group ->
        Enum.reject([group.snapshot_key, group.manifest_key], &MapSet.member?(externally_referenced_keys, &1))
    end)
    |> Enum.uniq()
  end

  defp portable_blob_storage_keys_from_artifact(artifact) do
    manifest_key = artifact.asset_manifest_storage_key
    snapshot_key = artifact.snapshot_storage_key

    with {:ok, expected_snapshot_key, blob_prefix} <- portable_artifact_namespaces(manifest_key),
         :ok <- validate_snapshot_ownership(snapshot_key, expected_snapshot_key),
         {:ok, snapshot} <- safe_load_snapshot(snapshot_key, :snapshot),
         {:ok, manifest} <- safe_load_snapshot(manifest_key, :asset_manifest),
         {:ok, assets} <- validate_asset_manifest(manifest),
         {:ok, keys} <- validate_manifest_asset_keys(assets, blob_prefix),
         :ok <- verify_artifact_checksum(artifact.checksum, snapshot, manifest) do
      {:ok, keys}
    else
      {:error, {:snapshot_unavailable, reason}} ->
        {:error, {:portable_snapshot_unavailable, snapshot_key, reason}}

      {:error, {:asset_manifest_unavailable, reason}} ->
        {:error, {:portable_asset_manifest_unavailable, manifest_key, reason}}

      {:error, reason}
      when reason in [
             :invalid_manifest,
             :invalid_assets,
             :invalid_asset_source_key,
             :conflicting_asset_source_keys
           ] ->
        {:error, {:template_asset_manifest_unreadable, manifest_key, :invalid_asset_manifest}}

      {:error, reason} ->
        {:error, {:invalid_portable_artifact, manifest_key, reason}}
    end
  end

  defp safe_load_snapshot(storage_key, artifact_type) do
    if artifact_type == :asset_manifest do
      :telemetry.execute(@manifest_load_event, %{count: 1}, %{storage_key: storage_key})
    end

    case SnapshotStorage.load_snapshot(storage_key) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, {unavailable_error(artifact_type), reason}}
    end
  rescue
    error ->
      {:error, {unavailable_error(artifact_type), {:load_exception, Exception.message(error)}}}
  catch
    kind, reason -> {:error, {unavailable_error(artifact_type), {:load_failure, kind, reason}}}
  end

  defp unavailable_error(:snapshot), do: :snapshot_unavailable
  defp unavailable_error(:asset_manifest), do: :asset_manifest_unavailable

  defp verify_artifact_checksum(checksum, snapshot, manifest) when is_binary(checksum) do
    calculated_checksum = Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => manifest})

    if Regex.match?(@sha256_regex, checksum) and Plug.Crypto.secure_compare(calculated_checksum, checksum) do
      :ok
    else
      {:error, :checksum_mismatch}
    end
  end

  defp verify_artifact_checksum(_checksum, _snapshot, _manifest), do: {:error, :missing_checksum}

  defp validate_asset_manifest(%{"format_version" => 1, "assets" => assets, "asset_count" => asset_count})
       when is_list(assets) and is_integer(asset_count) and asset_count == length(assets) do
    if Enum.all?(assets, &is_map/1) do
      {:ok, assets}
    else
      {:error, :invalid_assets}
    end
  end

  defp validate_asset_manifest(_manifest), do: {:error, :invalid_manifest}

  defp validate_manifest_asset_keys(assets, blob_prefix) do
    case Enum.reduce_while(assets, {:ok, %{}}, &reduce_manifest_asset(&1, &2, blob_prefix)) do
      {:ok, source_keys} -> {:ok, Map.values(source_keys)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reduce_manifest_asset(asset, {:ok, source_keys}, blob_prefix) do
    with {:ok, blob_hash, key} <- portable_asset_source(asset, blob_prefix),
         {:ok, source_keys} <- merge_asset_source(source_keys, blob_hash, key) do
      {:cont, {:ok, source_keys}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp portable_asset_source(%{"blob_hash" => blob_hash, "key" => key}, blob_prefix) do
    if valid_owned_portable_asset?(blob_hash, key, blob_prefix) do
      {:ok, blob_hash, key}
    else
      {:error, :invalid_asset_source_key}
    end
  end

  defp portable_asset_source(_asset, _blob_prefix), do: {:error, :invalid_asset_source_key}

  defp merge_asset_source(source_keys, blob_hash, key) do
    case Map.fetch(source_keys, blob_hash) do
      :error -> {:ok, Map.put(source_keys, blob_hash, key)}
      {:ok, ^key} -> {:ok, source_keys}
      {:ok, _different_key} -> {:error, :conflicting_asset_source_keys}
    end
  end

  defp valid_owned_portable_asset?(blob_hash, key, blob_prefix) when is_binary(blob_hash) and is_binary(key) do
    filename_prefix = "#{blob_prefix}#{blob_hash}/"

    Regex.match?(@sha256_regex, blob_hash) and
      Storage.canonical_key?(key) and
      String.starts_with?(key, filename_prefix) and
      safe_portable_filename?(String.replace_prefix(key, filename_prefix, ""))
  end

  defp valid_owned_portable_asset?(_blob_hash, _key, _blob_prefix), do: false

  defp safe_portable_filename?(filename) do
    filename != "" and not String.contains?(filename, "/")
  end

  defp portable_artifact_namespaces(manifest_key) when is_binary(manifest_key) do
    case String.split(manifest_key, "/", trim: false) do
      ["project_templates", "imports", slug, suffix, "asset-manifest.json.gz"]
      when slug != "" and suffix != "" ->
        if Storage.canonical_key?(manifest_key) do
          {:ok, "project_templates/imports/#{slug}/#{suffix}/snapshot.json.gz",
           "project_templates/imported_blobs/#{slug}/#{suffix}/"}
        else
          {:error, :invalid_manifest_storage_key}
        end

      _other ->
        {:error, :invalid_manifest_storage_key}
    end
  end

  defp portable_artifact_namespaces(_manifest_key), do: {:error, :invalid_manifest_storage_key}

  defp validate_snapshot_ownership(snapshot_key, expected_snapshot_key) when is_binary(snapshot_key) do
    if Storage.canonical_key?(snapshot_key) and snapshot_key == expected_snapshot_key do
      :ok
    else
      {:error, :invalid_snapshot_storage_key}
    end
  end

  defp validate_snapshot_ownership(_snapshot_key, _artifact_prefix), do: {:error, :invalid_snapshot_storage_key}

  defp portable_manifest_key?(key) when is_binary(key) do
    String.starts_with?(key, @portable_manifest_prefix)
  end

  defp portable_manifest_key?(_key), do: false

  defp valid_template_gc_key?(key) when is_binary(key) do
    Storage.canonical_key?(key) and
      (Regex.match?(@internal_artifact_key_regex, key) or
         portable_import_artifact_key?(key) or portable_blob_key?(key))
  end

  defp valid_template_gc_key?(_key), do: false

  defp portable_import_artifact_key?(key) do
    case String.split(key, "/", trim: false) do
      ["project_templates", "imports", slug, suffix, artifact_name] ->
        slug != "" and suffix != "" and
          artifact_name in ["snapshot.json.gz", "asset-manifest.json.gz"]

      _segments ->
        false
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

    case Enum.reject(storage_keys, &valid_template_gc_key?/1) do
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
          asset_manifest_storage_key: version.asset_manifest_storage_key,
          checksum: version.checksum
        }
      ),
      from(publication in ProjectTemplatePublication,
        where: publication.project_template_id == ^template_id,
        select: %{
          record_type: "publication",
          record_id: publication.id,
          snapshot_storage_key: publication.snapshot_storage_key,
          asset_manifest_storage_key: publication.asset_manifest_storage_key,
          checksum: publication.checksum
        }
      )
    ]
  end

  defp sort_artifact_ownership(ownership), do: Enum.sort_by(ownership, &{&1.record_type, &1.record_id})

  defp portable_blob_key?(key) do
    case String.split(key, "/", trim: false) do
      ["project_templates", "imported_blobs", slug, suffix, blob_hash, _filename]
      when slug != "" and suffix != "" ->
        valid_owned_portable_asset?(
          blob_hash,
          key,
          "project_templates/imported_blobs/#{slug}/#{suffix}/"
        )

      _segments ->
        false
    end
  end

  defp enqueue_artifact_gc([]), do: {:ok, nil}

  defp enqueue_artifact_gc(storage_keys) do
    %{"storage_keys" => storage_keys}
    |> DeleteProjectTemplateArtifactsWorker.new()
    |> Oban.insert()
  end
end
