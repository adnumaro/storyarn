defmodule Storyarn.ProjectTemplates.PortableBundle do
  @moduledoc false

  alias Storyarn.ProjectTemplates.Artifact

  @format_version 1
  @manifest_path "manifest.json"
  @snapshot_path "snapshot.json"
  @asset_manifest_path "asset_manifest.json"
  @required_paths [@manifest_path, @snapshot_path, @asset_manifest_path]

  def format_version, do: @format_version
  def manifest_path, do: @manifest_path
  def snapshot_path, do: @snapshot_path
  def asset_manifest_path, do: @asset_manifest_path

  def checksum(snapshot, asset_manifest, asset_blobs) do
    Artifact.checksum(%{
      "snapshot" => snapshot,
      "asset_manifest" => asset_manifest,
      "asset_blobs" => checksum_asset_blobs(asset_blobs)
    })
  end

  def write(path, manifest, snapshot, asset_manifest, asset_files) do
    files =
      [
        {@manifest_path, encode_json!(manifest)},
        {@snapshot_path, encode_json!(snapshot)},
        {@asset_manifest_path, encode_json!(asset_manifest)}
      ] ++ asset_files

    with :ok <- validate_output_path(path),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- validate_file_paths(files) do
      entries = Enum.map(files, fn {entry_path, data} -> {String.to_charlist(entry_path), IO.iodata_to_binary(data)} end)

      case :erl_tar.create(String.to_charlist(path), entries, [:compressed]) do
        :ok -> {:ok, path}
        {:error, reason} -> {:error, {:bundle_write_failed, reason}}
      end
    end
  end

  def read(path) do
    with {:ok, entries} <- extract_entries(path),
         {:ok, files} <- entries_to_file_map(entries),
         :ok <- require_entries(files),
         {:ok, manifest} <- decode_entry(files, @manifest_path),
         {:ok, snapshot} <- decode_entry(files, @snapshot_path),
         {:ok, asset_manifest} <- decode_entry(files, @asset_manifest_path) do
      {:ok, %{manifest: manifest, snapshot: snapshot, asset_manifest: asset_manifest, files: files}}
    end
  end

  def asset_files(files, manifest) do
    manifest
    |> Map.get("asset_blobs", [])
    |> Enum.map(fn blob ->
      path = blob["path"]
      {blob, Map.get(files, path)}
    end)
  end

  defp extract_entries(path) do
    case :erl_tar.extract(String.to_charlist(path), [:compressed, :memory]) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:bundle_read_failed, reason}}
    end
  end

  defp entries_to_file_map(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {path, data}, {:ok, files} ->
      path = List.to_string(path)

      cond do
        not safe_entry_path?(path) ->
          {:halt, {:error, {:unsafe_bundle_path, path}}}

        Map.has_key?(files, path) ->
          {:halt, {:error, {:duplicate_bundle_path, path}}}

        true ->
          {:cont, {:ok, Map.put(files, path, IO.iodata_to_binary(data))}}
      end
    end)
  end

  defp require_entries(files) do
    case Enum.find(@required_paths, &(not Map.has_key?(files, &1))) do
      nil -> :ok
      path -> {:error, {:missing_bundle_entry, path}}
    end
  end

  defp decode_entry(files, path) do
    files
    |> Map.fetch!(path)
    |> Jason.decode()
    |> case do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:invalid_bundle_json, path, reason}}
    end
  end

  defp validate_output_path(path) when is_binary(path) and byte_size(path) > 0, do: :ok
  defp validate_output_path(_path), do: {:error, :invalid_output_path}

  defp validate_file_paths(files) do
    case Enum.find(files, fn {path, _data} -> not safe_entry_path?(path) end) do
      nil -> :ok
      {path, _data} -> {:error, {:unsafe_bundle_path, path}}
    end
  end

  defp safe_entry_path?(path) when is_binary(path) do
    path != "" and
      Path.type(path) == :relative and
      not String.contains?(path, <<0>>) and
      not String.contains?(path, "\\") and
      path
      |> Path.split()
      |> Enum.all?(&(&1 not in [".", ".."]))
  end

  defp safe_entry_path?(_path), do: false

  defp checksum_asset_blobs(asset_blobs) do
    asset_blobs
    |> Enum.map(&Map.take(&1, ["asset_id", "sha256", "size", "content_type", "path", "filename"]))
    |> Enum.sort_by(&{&1["sha256"], &1["path"]})
  end

  defp encode_json!(data), do: Jason.encode_to_iodata!(data, pretty: true)
end
