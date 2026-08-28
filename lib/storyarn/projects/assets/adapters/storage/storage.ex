defmodule Storyarn.Projects.Assets.Storage do
  @moduledoc """
  Behaviour for asset storage backends.

  Supports both local file storage (development) and S3-compatible storage (production).
  """

  alias Storyarn.Projects.Assets.Storage.R2

  require Logger

  @type key :: String.t()
  @type url :: String.t()
  @type content_type :: String.t()
  @type binary_data :: binary()
  @type object_stat :: %{
          size: non_neg_integer(),
          etag: String.t() | nil,
          content_type: String.t() | nil
        }
  @type object_identity :: String.t()
  @type listed_object :: %{
          key: key(),
          size: non_neg_integer(),
          identity: object_identity()
        }
  @type listed_object_metadata :: %{key: key(), size: non_neg_integer()}
  @type list_page :: %{objects: [listed_object()], cursor: String.t() | nil}
  @type metadata_list_page :: %{objects: [listed_object_metadata()], cursor: String.t() | nil}
  @type conditional_copy_cleanup_error ::
          {:conditional_copy_cleanup_required, destination_created? :: boolean(), pending_cleanup_key :: key(),
           cleanup_reason :: term()}
  @type storage_write_cleanup_error ::
          {:storage_write_cleanup_required, cleanup_key :: key(), write_reason :: term(), cleanup_reason :: term()}

  @callback upload(key, binary_data, content_type) :: {:ok, url} | {:error, term()}
  @callback upload_stream(key, Enumerable.t(), content_type) :: {:ok, url} | {:error, term()}
  @callback abort_incomplete_multipart_uploads(key, opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback incomplete_multipart_upload_count(key, opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback put_if_absent(key, binary_data, content_type) ::
              {:ok, url, created? :: boolean()} | {:error, term()}
  @callback delete(key) :: :ok | {:error, term()}

  @doc """
  Deletes an object only when its opaque identity still matches the value
  returned by `list_prefix/2`.

  Backends without an atomic conditional delete must fail closed unless the
  caller holds an external write fence for the complete verify/delete operation.
  """
  @callback delete_if_matches(key, object_identity()) :: :ok | {:error, term()}
  @doc "Returns an opaque stable identity for the configured provider namespace."
  @callback namespace_fingerprint() :: {:ok, String.t()} | {:error, term()}
  @callback get_url(key) :: url
  @callback download(key) :: {:ok, binary_data} | {:error, term()}
  @callback stat(key) :: {:ok, object_stat} | {:error, term()}
  @callback stream(key, non_neg_integer(), non_neg_integer(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback presigned_upload_url(key, content_type, opts :: keyword()) ::
              {:ok, url, map()} | {:error, term()}
  @callback presigned_download_url(key, content_type, opts :: keyword()) ::
              {:ok, url} | {:error, term()}
  @callback copy(source_key :: key, dest_key :: key) :: :ok | {:error, term()}
  @callback copy_if_absent(source_key :: key, dest_key :: key) ::
              {:ok, created? :: boolean()} | {:error, term()}
  @callback key_from_url(url) :: {:ok, key} | {:error, :invalid_url}
  @callback list_prefix(String.t(), keyword()) :: {:ok, list_page()} | {:error, term()}
  @callback list_prefix_metadata(String.t(), keyword()) :: {:ok, metadata_list_page()} | {:error, term()}
  @optional_callbacks list_prefix_metadata: 2,
                      abort_incomplete_multipart_uploads: 2,
                      incomplete_multipart_upload_count: 2

  @snapshot_archive_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/snapshots/archives/v2/(?:staging|ready)/[A-Za-z0-9_-]{16}/(?:snapshot\.zip|manifest\.json)\z'
  @restore_staging_multipart_cleanup_key_pattern ~r'\Aprojects/[1-9][0-9]*/storage-reservations/v1/restore-staging/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z'
  @workspace_snapshot_import_multipart_cleanup_key_pattern ~r'\Aworkspace-snapshot-imports/v1/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(?:snapshot\.zip|blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31})\z'

  @doc "Returns the hard wall-clock deadline shared by UploadPart and cleanup quiescence."
  @spec multipart_upload_part_deadline_ms() :: pos_integer()
  def multipart_upload_part_deadline_ms do
    config = Application.fetch_env!(:storyarn, __MODULE__)

    case Keyword.fetch!(config, :multipart_upload_part_deadline_ms) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _invalid -> raise "invalid multipart UploadPart deadline"
    end
  end

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

  @doc """
  Returns the configured storage adapter.
  """
  def adapter do
    config = Application.get_env(:storyarn, :storage, [])

    case Keyword.get(config, :adapter, :local) do
      :local -> Storyarn.Projects.Assets.Storage.Local
      :r2 -> R2
      adapter when is_atom(adapter) -> adapter
    end
  end

  @doc "Returns whether the configured adapter supports direct external uploads."
  @spec external_upload?() :: boolean()
  def external_upload?, do: adapter() == R2

  @doc """
  Uploads a file to storage.
  """
  def upload(key, data, content_type) do
    adapter().upload(key, data, content_type)
  end

  @doc """
  Uploads a bounded stream without assembling the complete object in memory.

  Adapters must consume `{:ok, binary}` chunks and stop on `{:error, reason}`.
  S3-compatible adapters use multipart upload.
  """
  def upload_stream(key, chunks, content_type) do
    adapter().upload_stream(key, chunks, content_type)
  end

  @doc """
  Aborts every incomplete multipart upload owned by one exact canonical key.

  Cleanup calls this only after durable ownership and provider namespace have
  been revalidated. Adapters that do not use multipart uploads may omit the
  callback and are treated as having no incomplete uploads.
  """
  @spec abort_incomplete_multipart_uploads(key(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def abort_incomplete_multipart_uploads(key, opts \\ [])

  def abort_incomplete_multipart_uploads(key, opts) when is_binary(key) and is_list(opts) do
    if canonical_key?(key) and Keyword.keyword?(opts) do
      adapter = adapter()
      _loaded? = Code.ensure_loaded?(adapter)

      if function_exported?(adapter, :abort_incomplete_multipart_uploads, 2),
        do: adapter.abort_incomplete_multipart_uploads(key, opts),
        else: {:ok, 0}
    else
      {:error, :invalid_multipart_cleanup_request}
    end
  end

  def abort_incomplete_multipart_uploads(_key, _opts), do: {:error, :invalid_multipart_cleanup_request}

  @doc """
  Counts incomplete multipart uploads for one exact canonical cleanup key.

  This is read-only operational evidence. It does not grant deletion authority
  and adapters without exact multipart inventory must fail closed.
  """
  @spec incomplete_multipart_upload_count(key(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def incomplete_multipart_upload_count(key, opts \\ [])

  def incomplete_multipart_upload_count(key, opts) when is_binary(key) and is_list(opts) do
    if canonical_key?(key) and Keyword.keyword?(opts) do
      adapter = adapter()
      _loaded? = Code.ensure_loaded?(adapter)

      if function_exported?(adapter, :incomplete_multipart_upload_count, 2),
        do: adapter.incomplete_multipart_upload_count(key, opts),
        else: {:error, :multipart_inventory_not_supported}
    else
      {:error, :invalid_multipart_inventory_request}
    end
  end

  def incomplete_multipart_upload_count(_key, _opts), do: {:error, :invalid_multipart_inventory_request}

  @doc """
  Stores an object only when the key does not already exist.

  The returned boolean identifies which caller owns cleanup of the object.
  """
  def put_if_absent(key, data, content_type) do
    adapter().put_if_absent(key, data, content_type)
  end

  @doc """
  Downloads a file from storage, returning the raw binary content.
  """
  def download(key) do
    adapter().download(key)
  end

  @doc """
  Returns private object metadata without exposing a storage URL.
  """
  def stat(key) do
    adapter().stat(key)
  end

  @doc """
  Streams a byte window from private storage in bounded chunks.

  Stream elements are `{:ok, binary}` or `{:error, reason}`. Object-storage
  adapters sign each request server-side; no bearer URL is returned to callers.
  """
  def stream(key, offset, length, opts \\ []) do
    adapter().stream(key, offset, length, opts)
  end

  @doc "Lists one bounded page of object metadata beneath an exact prefix."
  def list_prefix(prefix, opts \\ []) when is_binary(prefix) and is_list(opts) do
    if canonical_prefix?(prefix) and Keyword.keyword?(opts),
      do: adapter().list_prefix(prefix, opts),
      else: {:error, :invalid_prefix}
  end

  @doc "Lists key and size metadata without requiring content-derived object identities."
  def list_prefix_metadata(prefix, opts \\ []) when is_binary(prefix) and is_list(opts) do
    if canonical_prefix?(prefix) and Keyword.keyword?(opts) do
      list_prefix_metadata_with_adapter(adapter(), prefix, opts)
    else
      {:error, :invalid_prefix}
    end
  end

  defp list_prefix_metadata_with_adapter(adapter, prefix, opts) do
    _loaded? = Code.ensure_loaded?(adapter)

    if function_exported?(adapter, :list_prefix_metadata, 2),
      do: adapter.list_prefix_metadata(prefix, opts),
      else: metadata_from_identity_page(adapter, prefix, opts)
  end

  defp metadata_from_identity_page(adapter, prefix, opts) do
    with {:ok, %{objects: objects, cursor: cursor}} <- adapter.list_prefix(prefix, opts) do
      {:ok, %{objects: Enum.map(objects, &Map.take(&1, [:key, :size])), cursor: cursor}}
    end
  end

  @doc "Returns the opaque identity of the configured provider namespace."
  def namespace_fingerprint do
    adapter().namespace_fingerprint()
  end

  @doc """
  Deletes a file from storage, except recoverable versioning blobs.

  Content-addressed blobs are recovery substrate and cannot be proven orphaned
  without a reachability-aware garbage collector.
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
        adapter().delete(key)
    end
  end

  @doc """
  Gets the storage URL persisted alongside a file.

  Private object-storage URLs must never be sent directly to browsers. Web
  surfaces use `StoryarnWeb.PrivateMedia` so access is authorized first.
  """
  def get_url(key) do
    adapter().get_url(key)
  end

  @doc """
  Generates a presigned URL for direct upload.

  Returns `{:ok, upload_url, form_data}` where form_data contains
  any additional fields needed for the upload.
  """
  def presigned_upload_url(key, content_type, opts \\ []) do
    adapter().presigned_upload_url(key, content_type, opts)
  end

  @doc """
  Generates a short-lived URL for a direct private download.

  The URL is a bearer credential and must only be returned after the caller
  has authorized the exact object. Download URLs are capped at five minutes;
  response metadata is fixed by the signature so browsers receive a private
  attachment rather than provider defaults.
  """
  def presigned_download_url(key, content_type, opts \\ []) do
    with true <- canonical_key?(key),
         true <- valid_download_content_type?(content_type),
         true <- Keyword.keyword?(opts),
         {:ok, expires_in} <- download_expiry(opts),
         {:ok, filename} <- download_filename(opts) do
      adapter().presigned_download_url(key, content_type,
        expires_in: expires_in,
        filename: filename
      )
    else
      _invalid -> {:error, :invalid_presigned_download_request}
    end
  end

  @doc """
  Copies a file from one storage key to another.
  """
  def copy(source_key, dest_key) do
    adapter().copy(source_key, dest_key)
  end

  @doc """
  Copies an object only when the destination key does not already exist.

  The returned boolean identifies which caller owns cleanup of the destination.

  An adapter that atomically publishes the destination but cannot remove an
  intermediate object returns
  `{:error, {:conditional_copy_cleanup_required, created?, cleanup_key, reason}}`.
  The caller must hand `cleanup_key` to durable compensation and must also
  compensate the destination when `created?` is true.
  """
  def copy_if_absent(source_key, dest_key) do
    adapter().copy_if_absent(source_key, dest_key)
  end

  @doc """
  Uses conditional server-side copy when available and falls back to a bounded
  private read plus streaming/multipart upload.

  The fallback is intended for immutable snapshot-owned namespaces. Callers
  must verify the destination digest and size before publishing readiness.
  """
  def copy_if_absent_or_stream(source_key, dest_key, size_bytes, content_type)
      when is_integer(size_bytes) and size_bytes >= 0 do
    case copy_if_absent(source_key, dest_key) do
      {:error, reason} when reason in [:not_supported, :copy_not_supported] ->
        copy_via_stream(source_key, dest_key, size_bytes, content_type)

      {:error, {:http_error, status, _response}} when status in [405, 501] ->
        copy_via_stream(source_key, dest_key, size_bytes, content_type)

      result ->
        result
    end
  end

  defp copy_via_stream(source_key, dest_key, size_bytes, content_type) do
    case stat(dest_key) do
      {:ok, _stat} ->
        {:ok, false}

      {:error, reason} when reason == :enoent ->
        with {:ok, chunks} <- stream(source_key, 0, size_bytes),
             {:ok, _url} <- upload_stream(dest_key, chunks, content_type) do
          {:ok, true}
        end

      {:error, {:http_error, 404, _response}} ->
        with {:ok, chunks} <- stream(source_key, 0, size_bytes),
             {:ok, _url} <- upload_stream(dest_key, chunks, content_type) do
          {:ok, true}
        end

      {:error, reason} ->
        {:error, {:destination_stat_failed, reason}}
    end
  end

  @doc """
  Extracts a storage key from a URL previously returned by the adapter.

  This is used only to migrate legacy persisted URLs into the authenticated
  delivery path. It does not authorize access to the resulting key.
  """
  def key_from_url(url) do
    adapter().key_from_url(url)
  end

  defp download_expiry(opts) do
    case Keyword.get(opts, :expires_in, 300) do
      expires_in when is_integer(expires_in) and expires_in > 0 and expires_in <= 300 ->
        {:ok, expires_in}

      _invalid ->
        {:error, :invalid_expiry}
    end
  end

  defp download_filename(opts) do
    case Keyword.get(opts, :filename) do
      filename when is_binary(filename) and byte_size(filename) > 0 and byte_size(filename) <= 255 ->
        if String.valid?(filename) and not String.contains?(filename, ["\r", "\n", "\"", "\\", <<0>>]),
          do: {:ok, filename},
          else: {:error, :invalid_filename}

      _invalid ->
        {:error, :invalid_filename}
    end
  end

  defp valid_download_content_type?(content_type) when is_binary(content_type) do
    byte_size(content_type) in 1..255 and String.valid?(content_type) and
      not String.contains?(content_type, ["\r", "\n", <<0>>])
  end

  defp valid_download_content_type?(_content_type), do: false

  defp recoverable_blob_key?(key) when is_binary(key) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "blobs" | tail] ->
        valid_project_id?(project_id) and valid_key_tail?(tail)

      _segments ->
        false
    end
  end

  defp recoverable_blob_key?(_key), do: false

  @doc false
  @spec canonical_key?(term()) :: boolean()
  def canonical_key?(key) when is_binary(key) do
    key != "" and
      String.valid?(key) and
      not String.contains?(key, [<<0>>, "\\"]) and
      canonical_segments?(String.split(key, "/", trim: false))
  end

  def canonical_key?(_key), do: false

  @doc false
  @spec canonical_prefix?(term()) :: boolean()
  def canonical_prefix?(prefix) when is_binary(prefix) do
    String.ends_with?(prefix, "/") and not String.ends_with?(prefix, "//") and
      canonical_key?(String.trim_trailing(prefix, "/"))
  end

  def canonical_prefix?(_prefix), do: false

  defp canonical_segments?(segments) do
    segments != [] and
      Enum.all?(segments, fn segment ->
        segment != "" and segment not in [".", ".."]
      end)
  end

  defp valid_project_id?(project_id) do
    case Integer.parse(project_id) do
      {id, ""} when id > 0 -> true
      _invalid_id -> false
    end
  end

  defp valid_key_tail?(tail) do
    canonical_segments?(tail)
  end
end
