defmodule Storyarn.Projects.Assets.Storage do
  @moduledoc """
  Project-owned object-storage policy boundary.

  Provider I/O lives in `Storyarn.Platform.ObjectStorage`. This module keeps the
  Project-specific multipart cleanup grammar and prevents ordinary deletion of
  recoverable blobs until Projects can prove they are unreachable.
  """

  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Projects.Assets.StorageKey

  require Logger

  @type key :: ObjectStorage.key()
  @type url :: ObjectStorage.url()
  @type content_type :: ObjectStorage.content_type()
  @type binary_data :: ObjectStorage.binary_data()
  @type object_stat :: ObjectStorage.object_stat()
  @type object_identity :: ObjectStorage.object_identity()
  @type listed_object :: ObjectStorage.listed_object()
  @type listed_object_metadata :: ObjectStorage.listed_object_metadata()
  @type list_page :: ObjectStorage.list_page()
  @type metadata_list_page :: ObjectStorage.metadata_list_page()
  @type conditional_copy_cleanup_error :: ObjectStorage.conditional_copy_cleanup_error()
  @type storage_write_cleanup_error :: ObjectStorage.storage_write_cleanup_error()

  @snapshot_archive_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/(?:snapshot\.zip|manifest\.json)\z'
  @restore_staging_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/storage-reservations/v1/restore-staging/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z'
  @workspace_snapshot_import_multipart_cleanup_key_pattern ~r'\Aworkspace-snapshot-imports/v1/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(?:snapshot\.zip|blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31})\z'

  @spec multipart_upload_part_deadline_ms() :: pos_integer()
  defdelegate multipart_upload_part_deadline_ms(), to: ObjectStorage

  @doc "Returns the cleanup quiescence window with a database-clock precision margin."
  @spec multipart_cleanup_quiescence_seconds() :: pos_integer()
  def multipart_cleanup_quiescence_seconds do
    timeout_ms = multipart_upload_part_deadline_ms()

    # Cleanup receipts use second-precision timestamps. One extra second keeps
    # the real elapsed window at or above the UploadPart deadline even when the
    # database clock is truncated immediately before the next whole second.
    div(timeout_ms + 999, 1_000) + 1
  end

  @doc false
  @spec multipart_cleanup_key?(term()) :: boolean()
  def multipart_cleanup_key?(key) when is_binary(key),
    do:
      Regex.match?(@snapshot_archive_multipart_cleanup_key_pattern, key) or
        Regex.match?(@restore_staging_multipart_cleanup_key_pattern, key) or
        Regex.match?(@workspace_snapshot_import_multipart_cleanup_key_pattern, key)

  def multipart_cleanup_key?(_key), do: false

  defdelegate external_upload?(), to: ObjectStorage
  defdelegate upload(key, data, content_type), to: ObjectStorage
  defdelegate upload_stream(key, chunks, content_type), to: ObjectStorage
  defdelegate put_if_absent(key, data, content_type), to: ObjectStorage
  defdelegate download(key), to: ObjectStorage
  defdelegate stat(key), to: ObjectStorage
  defdelegate stream(key, offset, length, opts \\ []), to: ObjectStorage
  defdelegate list_prefix(prefix, opts \\ []), to: ObjectStorage
  defdelegate list_prefix_metadata(prefix, opts \\ []), to: ObjectStorage
  defdelegate namespace_fingerprint(), to: ObjectStorage
  defdelegate get_url(key), to: ObjectStorage
  defdelegate presigned_upload_url(key, content_type, opts \\ []), to: ObjectStorage
  defdelegate presigned_download_url(key, content_type, opts \\ []), to: ObjectStorage
  defdelegate copy(source_key, destination_key), to: ObjectStorage
  defdelegate copy_if_absent(source_key, destination_key), to: ObjectStorage
  defdelegate copy_if_absent_or_stream(source_key, destination_key, size_bytes, content_type), to: ObjectStorage
  defdelegate key_from_url(url), to: ObjectStorage
  defdelegate delete_if_matches(key, expected_identity), to: ObjectStorage
  defdelegate canonical_key?(key), to: StorageKey, as: :canonical?
  defdelegate canonical_prefix?(prefix), to: StorageKey, as: :canonical_prefix?

  @spec abort_incomplete_multipart_uploads(key(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def abort_incomplete_multipart_uploads(key, opts \\ [])

  def abort_incomplete_multipart_uploads(key, opts) when is_binary(key) and is_list(opts) do
    cond do
      not canonical_key?(key) or not Keyword.keyword?(opts) ->
        {:error, :invalid_multipart_cleanup_request}

      not multipart_cleanup_key?(key) ->
        {:ok, 0}

      true ->
        ObjectStorage.abort_incomplete_multipart_uploads(key, opts)
    end
  end

  def abort_incomplete_multipart_uploads(_key, _opts), do: {:error, :invalid_multipart_cleanup_request}

  @spec incomplete_multipart_upload_count(key(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def incomplete_multipart_upload_count(key, opts \\ [])

  def incomplete_multipart_upload_count(key, opts) when is_binary(key) and is_list(opts) do
    cond do
      not canonical_key?(key) or not Keyword.keyword?(opts) ->
        {:error, :invalid_multipart_inventory_request}

      not multipart_cleanup_key?(key) ->
        {:error, :invalid_multipart_inventory_request}

      true ->
        ObjectStorage.incomplete_multipart_upload_count(key, opts)
    end
  end

  def incomplete_multipart_upload_count(_key, _opts), do: {:error, :invalid_multipart_inventory_request}

  @doc """
  Deletes a Project storage object unless it belongs to the recoverable blob
  namespace. Reachability-aware cleanup must use the Projects reconciliation
  workflow instead.
  """
  def delete(key) do
    cond do
      not canonical_key?(key) ->
        Logger.warning("Blocked deletion for a non-canonical storage key")

        :telemetry.execute(
          [:storyarn, :assets, :storage, :invalid_delete_blocked],
          %{count: 1},
          %{}
        )

        {:error, :invalid_key}

      recoverable_blob_key?(key) ->
        Logger.warning("Blocked deletion of a recoverable versioning blob")

        :telemetry.execute(
          [:storyarn, :assets, :storage, :recoverable_blob_delete_blocked],
          %{count: 1},
          %{}
        )

        {:error, :recoverable_blob}

      true ->
        ObjectStorage.delete(key)
    end
  end

  @doc false
  @spec delete_after_policy_check(key()) :: :ok | {:error, term()}
  def delete_after_policy_check(key) do
    ObjectStorage.delete(key)
  end

  defp recoverable_blob_key?(key) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "blobs" | tail] ->
        valid_project_id?(project_id) and valid_key_tail?(tail)

      _segments ->
        false
    end
  end

  defp valid_project_id?(project_id) do
    case Integer.parse(project_id) do
      {id, ""} when id > 0 -> true
      _invalid_id -> false
    end
  end

  defp valid_key_tail?(tail) do
    tail != [] and Enum.all?(tail, &(&1 != "" and &1 not in [".", ".."]))
  end
end
