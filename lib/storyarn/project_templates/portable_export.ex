defmodule Storyarn.ProjectTemplates.PortableExport do
  @moduledoc false

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers

  @spec export_project(pos_integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def export_project(project_id, output_path, opts \\ []) when is_integer(project_id) and is_binary(output_path) do
    with %Project{} = project <- Repo.get(Project, project_id),
         :ok <- ensure_exportable_project(project),
         {:ok, audit_report, snapshot} <- Audit.run_with_snapshot(project.id),
         asset_manifest = Artifact.build_asset_manifest(project.id),
         referenced_asset_ids = referenced_asset_ids(snapshot),
         asset_manifest = filter_asset_manifest(asset_manifest, referenced_asset_ids),
         {:ok, asset_files, asset_blobs} <- build_asset_files(asset_manifest),
         manifest = build_manifest(project, opts, audit_report, snapshot, asset_manifest, asset_blobs),
         {:ok, _path} <- PortableBundle.write(output_path, manifest, snapshot, asset_manifest, asset_files) do
      {:ok, %{path: output_path, manifest: manifest}}
    else
      nil -> {:error, :project_not_found}
      {:error, %{"status" => "failed"} = report} -> {:error, {:audit_failed, report}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_exportable_project(%Project{deleted_at: nil}), do: :ok
  defp ensure_exportable_project(%Project{}), do: {:error, :project_deleted}

  defp build_manifest(project, opts, audit_report, snapshot, asset_manifest, asset_blobs) do
    name = option(opts, :name) || project.name
    slug = option(opts, :slug) || NameNormalizer.slugify(name)
    description = option(opts, :description) || project.description

    %{
      "format_version" => PortableBundle.format_version(),
      "exported_at" => DateTime.to_iso8601(TimeHelpers.now()),
      "source_project" => %{
        "id" => project.id,
        "name" => project.name
      },
      "template" => %{
        "name" => name,
        "slug" => slug,
        "description" => description,
        "version_notes" => option(opts, :version_notes)
      },
      "audit_report" => audit_report,
      "entity_counts" => Map.get(snapshot, "entity_counts", %{}),
      "asset_count" => length(asset_blobs),
      "asset_blobs" => asset_blobs,
      "checksum" => PortableBundle.checksum(snapshot, asset_manifest, asset_blobs)
    }
  end

  defp build_asset_files(asset_manifest) do
    asset_manifest
    |> Map.get("assets", [])
    |> Enum.reduce_while({:ok, [], []}, fn asset, {:ok, files, blobs} ->
      case build_asset_file(asset) do
        {:ok, path, data, blob} ->
          {:cont, {:ok, [{path, data} | files], [blob | blobs]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, files, blobs} -> {:ok, Enum.reverse(files), Enum.reverse(blobs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_asset_file(asset) do
    with blob_hash when is_binary(blob_hash) and byte_size(blob_hash) == 64 <- asset["blob_hash"],
         key when is_binary(key) and key != "" <- asset["key"],
         {:ok, data} <- Storage.download(key),
         ^blob_hash <- BlobStore.compute_hash(data) do
      filename = portable_asset_filename(asset)
      path = "assets/#{blob_hash}/#{asset["id"]}-#{filename}"

      blob = %{
        "asset_id" => asset["id"],
        "path" => path,
        "sha256" => blob_hash,
        "filename" => filename,
        "content_type" => asset["content_type"],
        "size" => byte_size(data)
      }

      {:ok, path, data, blob}
    else
      nil -> {:error, {:missing_asset_blob_hash, asset["id"]}}
      "" -> {:error, {:missing_asset_blob_hash, asset["id"]}}
      {:error, reason} -> {:error, {:asset_download_failed, asset["id"], reason}}
      _hash_mismatch -> {:error, {:asset_checksum_mismatch, asset["id"]}}
    end
  end

  defp referenced_asset_ids(snapshot) do
    snapshot
    |> collect_asset_blob_hash_keys(MapSet.new())
    |> MapSet.to_list()
  end

  defp collect_asset_blob_hash_keys(%{"asset_blob_hashes" => hashes} = map, ids) when is_map(hashes) do
    ids =
      hashes
      |> Map.keys()
      |> Enum.reduce(ids, &MapSet.put(&2, to_string(&1)))

    map
    |> Map.delete("asset_blob_hashes")
    |> collect_asset_blob_hash_keys(ids)
  end

  defp collect_asset_blob_hash_keys(map, ids) when is_map(map) do
    Enum.reduce(map, ids, fn {_key, value}, acc -> collect_asset_blob_hash_keys(value, acc) end)
  end

  defp collect_asset_blob_hash_keys(list, ids) when is_list(list) do
    Enum.reduce(list, ids, &collect_asset_blob_hash_keys/2)
  end

  defp collect_asset_blob_hash_keys(_value, ids), do: ids

  defp filter_asset_manifest(asset_manifest, asset_ids) do
    assets =
      asset_manifest
      |> Map.get("assets", [])
      |> Enum.filter(&(to_string(&1["id"]) in asset_ids))

    asset_manifest
    |> Map.put("assets", assets)
    |> Map.put("asset_count", length(assets))
  end

  defp portable_asset_filename(asset) do
    filename =
      asset["filename"]
      |> safe_string()
      |> Assets.sanitize_filename()

    if filename == "" do
      "#{asset["blob_hash"]}.#{BlobStore.ext_from_content_type(asset["content_type"])}"
    else
      filename
    end
  end

  defp option(opts, key) do
    cond do
      is_list(opts) ->
        Keyword.get(opts, key) || Enum.find_value(opts, &matching_option(&1, key))

      is_map(opts) ->
        Map.get(opts, key) || Map.get(opts, to_string(key))

      true ->
        nil
    end
  end

  defp matching_option({option_key, value}, key) do
    if to_string(option_key) == to_string(key), do: value
  end

  defp safe_string(nil), do: ""
  defp safe_string(value), do: to_string(value)
end
