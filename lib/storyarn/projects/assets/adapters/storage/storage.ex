defmodule Storyarn.Projects.Assets.Storage do
  @moduledoc """
  Project-owned object-storage policy boundary.

  Provider I/O lives in `Storyarn.Platform.ObjectStorage`. This module keeps the
  Project-specific multipart cleanup grammar and prevents ordinary deletion of
  recoverable blobs until Projects can prove they are unreachable.
  """

  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Projects.Assets.StorageCleanupOwnership
  alias Storyarn.Projects.Assets.StorageKey
  alias Storyarn.Projects.Assets.StorageKeyLock

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
  @type incomplete_multipart_summary :: ObjectStorage.incomplete_multipart_summary()
  @type incomplete_multipart_upload :: ObjectStorage.incomplete_multipart_upload()
  @type incomplete_multipart_upload_inventory :: ObjectStorage.incomplete_multipart_upload_inventory()
  @type multipart_upload_state :: ObjectStorage.multipart_upload_state()
  @type conditional_copy_cleanup_error :: ObjectStorage.conditional_copy_cleanup_error()
  @type storage_write_cleanup_error :: ObjectStorage.storage_write_cleanup_error()

  @snapshot_archive_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/(?:snapshot\.zip|manifest\.json)\z'
  @restore_staging_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/storage-reservations/v1/restore-staging/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z'
  @workspace_snapshot_import_multipart_cleanup_key_pattern ~r'\Aworkspace-snapshot-imports/v1/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(?:snapshot\.zip|blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31})\z'

  @spec multipart_upload_part_deadline_ms() :: pos_integer()
  defdelegate multipart_upload_part_deadline_ms(), to: ObjectStorage

  @spec multipart_upload_total_deadline_ms() :: pos_integer()
  defdelegate multipart_upload_total_deadline_ms(), to: ObjectStorage

  @doc "Returns the cleanup quiescence window with a database-clock precision margin."
  @spec multipart_cleanup_quiescence_seconds() :: pos_integer()
  def multipart_cleanup_quiescence_seconds do
    timeout_ms = multipart_upload_total_deadline_ms()

    # Cleanup receipts use second-precision timestamps. One extra second keeps
    # the real elapsed window at or above the full bounded-writer deadline even
    # when the database clock is truncated immediately before the next second.
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
  defdelegate with_operation_deadline(fun), to: ObjectStorage
  defdelegate with_operation_deadline(timeout_ms, fun), to: ObjectStorage

  def upload(key, data, content_type) do
    guarded_object_write(key, :unconditional, fn -> ObjectStorage.upload(key, data, content_type) end)
  end

  def upload_stream(key, chunks, content_type) do
    guarded_object_write(key, :unconditional, fn -> ObjectStorage.upload_stream(key, chunks, content_type) end)
  end

  def put_if_absent(key, data, content_type) do
    guarded_object_write(key, :conditional, fn -> ObjectStorage.put_if_absent(key, data, content_type) end)
  end

  defdelegate download(key), to: ObjectStorage
  defdelegate stat(key), to: ObjectStorage
  defdelegate object_probe(key), to: ObjectStorage
  defdelegate stream(key, offset, length, opts \\ []), to: ObjectStorage
  defdelegate list_prefix(prefix, opts \\ []), to: ObjectStorage
  defdelegate list_prefix_metadata(prefix, opts \\ []), to: ObjectStorage
  defdelegate incomplete_multipart_upload_summary(prefix, opts \\ []), to: ObjectStorage

  @doc """
  Returns the current provider namespace identity from local metadata only.

  Adapters must not perform HTTP or other remote provider I/O here: R2 hashes
  configuration and Local inspects its safe root identity. Fresh reads are safe
  under a database checkout and must never substitute a previously captured value.
  """
  @spec namespace_fingerprint() :: {:ok, String.t()} | {:error, term()}
  def namespace_fingerprint do
    case ObjectStorage.namespace_fingerprint() do
      {:ok, fingerprint} when is_binary(fingerprint) ->
        if valid_namespace_fingerprint?(fingerprint),
          do: {:ok, fingerprint},
          else: {:error, :invalid_storage_provider_namespace_fingerprint}

      {:error, _reason} = error ->
        error

      _invalid ->
        {:error, :invalid_storage_provider_namespace_fingerprint}
    end
  end

  @doc false
  @spec valid_namespace_fingerprint?(term()) :: boolean()
  def valid_namespace_fingerprint?(fingerprint) when is_binary(fingerprint),
    do: byte_size(fingerprint) == 64 and String.match?(fingerprint, ~r/\A[0-9a-f]{64}\z/)

  def valid_namespace_fingerprint?(_fingerprint), do: false

  defdelegate get_url(key), to: ObjectStorage

  def presigned_upload_url(key, content_type, opts \\ []) do
    with :ok <- ensure_write_not_handed_off(key) do
      # A bearer PUT cannot be revoked by admission or bounded by the server's
      # write deadline. Protected keys must use the server upload path instead.
      if multipart_cleanup_key?(key),
        do: {:error, :presigned_upload_requires_server_upload},
        else: ObjectStorage.presigned_upload_url(key, content_type, opts)
    end
  end

  defdelegate presigned_download_url(key, content_type, opts \\ []), to: ObjectStorage

  def copy(source_key, destination_key) do
    guarded_object_write(destination_key, :unconditional, fn -> ObjectStorage.copy(source_key, destination_key) end)
  end

  def copy_if_absent(source_key, destination_key) do
    guarded_object_write(destination_key, :conditional, fn ->
      ObjectStorage.copy_if_absent(source_key, destination_key)
    end)
  end

  def copy_if_absent_or_stream(source_key, destination_key, size_bytes, content_type) do
    guarded_object_write(destination_key, :conditional, fn ->
      ObjectStorage.copy_if_absent_or_stream(source_key, destination_key, size_bytes, content_type)
    end)
  end

  defdelegate key_from_url(url), to: ObjectStorage
  defdelegate delete_if_matches(key, expected_identity), to: ObjectStorage
  defdelegate canonical_key?(key), to: StorageKey, as: :canonical?
  defdelegate canonical_prefix?(prefix), to: StorageKey, as: :canonical_prefix?

  defp ensure_write_not_handed_off(key) do
    cond do
      not canonical_key?(key) -> {:error, :invalid_key}
      StorageCleanupOwnership.handed_off_for_key?(key) -> {:error, :storage_key_cleanup_handed_off}
      true -> :ok
    end
  rescue
    _exception -> {:error, :storage_write_fence_unavailable}
  catch
    _kind, _reason -> {:error, :storage_write_fence_unavailable}
  end

  defp guarded_object_write(key, ownership, write_fun)
       when ownership in [:unconditional, :conditional] and is_function(write_fun, 0) do
    if multipart_cleanup_key?(key) do
      guarded_multipart_object_write(key, ownership, write_fun)
    else
      with :ok <- ensure_write_not_handed_off(key) do
        finalize_guarded_object_write(write_fun.(), key, ownership)
      end
    end
  end

  defp guarded_multipart_object_write(key, ownership, write_fun) do
    ObjectStorage.with_operation_deadline(multipart_upload_total_deadline_ms(), fn ->
      with :ok <- guarded_storage_key_admission(key) do
        finalize_guarded_object_write(write_fun.(), key, ownership)
      end
    end)
  end

  defp guarded_storage_key_admission(key) do
    StorageKeyLock.transact_with_storage_key_admission(key, fn ->
      ensure_write_not_handed_off(key)
    end)
  end

  defp finalize_guarded_object_write(result, key, ownership) do
    case successful_object_write?(result, ownership) do
      :created -> finalize_created_object_write(result, key)
      :unowned -> finalize_unowned_object_write(result, key)
      :failed -> result
    end
  end

  defp finalize_created_object_write(result, key) do
    case ensure_write_not_handed_off(key) do
      :ok ->
        result

      {:error, reason} ->
        # The live durable cleanup request remains the source of truth. Its
        # quiescence window outlives every bounded provider write, so a failed
        # best-effort delete is observed and retried by the same request.
        _cleanup_result = ObjectStorage.delete(key)
        {:error, reason}
    end
  end

  # A successful unconditional write can overwrite an already-owned object.
  # Only the durable cleanup policy may decide whether those bytes are deletable.
  defp finalize_unowned_object_write(result, key) do
    case ensure_write_not_handed_off(key) do
      :ok -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp successful_object_write?(:ok, :unconditional), do: :unowned
  defp successful_object_write?({:ok, _value}, :unconditional), do: :unowned
  defp successful_object_write?({:ok, _url, _metadata}, :unconditional), do: :unowned
  defp successful_object_write?({:ok, true}, :conditional), do: :created
  defp successful_object_write?({:ok, false}, :conditional), do: :unowned
  defp successful_object_write?({:ok, _url, true}, :conditional), do: :created
  defp successful_object_write?({:ok, _url, false}, :conditional), do: :unowned
  defp successful_object_write?(_result, _ownership), do: :failed

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

  @spec list_incomplete_multipart_uploads(key(), keyword()) ::
          {:ok, incomplete_multipart_upload_inventory()} | {:error, term()}
  def list_incomplete_multipart_uploads(key, opts \\ [])

  def list_incomplete_multipart_uploads(key, opts) when is_binary(key) and is_list(opts) do
    cond do
      not canonical_key?(key) or not Keyword.keyword?(opts) ->
        {:error, :invalid_multipart_inventory_request}

      not multipart_cleanup_key?(key) ->
        {:error, :invalid_multipart_inventory_request}

      true ->
        ObjectStorage.list_incomplete_multipart_uploads(key, opts)
    end
  end

  def list_incomplete_multipart_uploads(_key, _opts), do: {:error, :invalid_multipart_inventory_request}

  @spec abort_incomplete_multipart_upload(key(), String.t()) :: :ok | {:error, term()}
  def abort_incomplete_multipart_upload(key, upload_id) when is_binary(key) and is_binary(upload_id) do
    if multipart_cleanup_key?(key),
      do: ObjectStorage.abort_incomplete_multipart_upload(key, upload_id),
      else: {:error, :invalid_multipart_upload_reference}
  end

  def abort_incomplete_multipart_upload(_key, _upload_id), do: {:error, :invalid_multipart_upload_reference}

  @spec incomplete_multipart_upload_state(key(), String.t()) ::
          {:ok, multipart_upload_state()} | {:error, term()}
  def incomplete_multipart_upload_state(key, upload_id) when is_binary(key) and is_binary(upload_id) do
    if multipart_cleanup_key?(key),
      do: ObjectStorage.incomplete_multipart_upload_state(key, upload_id),
      else: {:error, :invalid_multipart_upload_reference}
  end

  def incomplete_multipart_upload_state(_key, _upload_id), do: {:error, :invalid_multipart_upload_reference}

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
