defmodule Storyarn.Commercial.Billing.StorageProtocol do
  @moduledoc """
  Commercial's local copy of the persisted storage protocol it verifies.

  These values are deliberately duplicated from the Project snapshot writer.
  They form the database/object contract between the two bounded contexts;
  neither context needs to compile against the other's implementation.
  """

  @snapshot_format_version 2
  @snapshot_token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @project_blob_regex ~r|\Aprojects/([1-9]\d*)/blobs/([0-9a-f]{64})\.([^/]+)\z|
  @temporary_copy_marker ".storyarn-copy-"
  @max_project_id 9_223_372_036_854_775_807

  @hard_limits %{
    max_assets: 10_000,
    max_objects: 10_001,
    max_asset_bytes: 52_428_800,
    max_project_bytes: 128 * 1024 * 1024,
    max_manifest_bytes: 8 * 1024 * 1024,
    max_total_bytes: 500 * 1024 * 1024 * 1024,
    max_metadata_bytes: 64 * 1024,
    max_metadata_depth: 8
  }

  @spec staging_prefix(pos_integer(), String.t()) :: String.t()
  def staging_prefix(project_id, token),
    do: "projects/#{project_id}/snapshots/archives/v#{@snapshot_format_version}/staging/#{token}"

  @spec archive_key(String.t()) :: String.t()
  def archive_key(prefix) when is_binary(prefix), do: prefix <> "/snapshot.zip"

  @spec manifest_key(String.t()) :: String.t()
  def manifest_key(prefix) when is_binary(prefix), do: prefix <> "/manifest.json"

  @doc "Returns the persisted token when the prefix belongs to the exact Project snapshot namespace."
  @spec ready_prefix_token(pos_integer(), term()) :: {:ok, String.t()} | :error
  def ready_prefix_token(project_id, prefix) when is_integer(project_id) and project_id > 0 and is_binary(prefix) do
    case String.split(prefix, "/", trim: false) do
      ["projects", encoded_project_id, "snapshots", "archives", "v2", "ready", token] ->
        if encoded_project_id == Integer.to_string(project_id) and Regex.match?(@snapshot_token_regex, token),
          do: {:ok, token},
          else: :error

      _parts ->
        :error
    end
  end

  def ready_prefix_token(_project_id, _prefix), do: :error

  @spec ready_prefix_for_project?(pos_integer(), term()) :: boolean()
  def ready_prefix_for_project?(project_id, prefix), do: match?({:ok, _token}, ready_prefix_token(project_id, prefix))

  @doc "Returns whether a key is one of the two canonical objects beneath an already validated prefix."
  @spec snapshot_object_key?(String.t(), term()) :: boolean()
  def snapshot_object_key?(prefix, key) when is_binary(prefix) and is_binary(key) do
    key == archive_key(prefix) or key == manifest_key(prefix)
  end

  def snapshot_object_key?(_prefix, _key), do: false

  @spec hard_limits() :: map()
  def hard_limits, do: @hard_limits

  @spec canonical_key?(term()) :: boolean()
  def canonical_key?(key) when is_binary(key) do
    key != "" and String.valid?(key) and not String.contains?(key, [<<0>>, "\\"]) and
      canonical_segments?(String.split(key, "/", trim: false))
  end

  def canonical_key?(_key), do: false

  @spec project_blob_identity(term()) :: {:ok, pos_integer(), String.t()} | :error
  def project_blob_identity(storage_key) when is_binary(storage_key) do
    case Regex.run(@project_blob_regex, storage_key, capture: :all_but_first) do
      [project_id, hash, extension] -> parse_project_blob_identity(project_id, hash, extension)
      _match -> :error
    end
  end

  def project_blob_identity(_storage_key), do: :error

  defp parse_project_blob_identity(project_id, hash, extension) do
    with false <- String.contains?(extension, @temporary_copy_marker),
         {project_id, ""} when project_id > 0 and project_id <= @max_project_id <- Integer.parse(project_id) do
      {:ok, project_id, hash}
    else
      _invalid -> :error
    end
  end

  defp canonical_segments?(segments) do
    segments != [] and Enum.all?(segments, &(&1 != "" and &1 not in [".", ".."]))
  end
end
