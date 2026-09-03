defmodule Storyarn.Platform.ObjectStorage do
  @moduledoc """
  Provider-neutral object-storage contract and dispatcher.

  Supports both local file storage (development) and S3-compatible storage (production).
  """

  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Platform.ObjectStorage.Adapters.Local.ConditionalCopyRegistry
  alias Storyarn.Platform.ObjectStorage.Adapters.Local.ConditionalCopySweeper
  alias Storyarn.Platform.ObjectStorage.Adapters.R2
  alias Storyarn.Platform.ObjectStorage.Hashing
  alias Storyarn.Platform.ObjectStorage.KeyLock

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
  @type incomplete_multipart_summary :: %{
          count: non_neg_integer(),
          oldest_initiated_at: DateTime.t() | nil,
          inventory_complete: boolean()
        }
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
  @callback incomplete_multipart_upload_summary(:all | String.t(), opts :: keyword()) ::
              {:ok, incomplete_multipart_summary()} | {:error, term()}
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
                      incomplete_multipart_upload_count: 2,
                      incomplete_multipart_upload_summary: 2

  @legacy_config_key :"Elixir.Storyarn.Projects.Assets.Storage"

  @doc false
  @spec child_specs() :: [module()]
  def child_specs do
    [ConditionalCopyRegistry, ConditionalCopySweeper]
  end

  defdelegate sha256_chunks(chunks), to: Hashing
  defdelegate with_storage_key_lock(storage_key, fun), to: KeyLock
  defdelegate with_storage_key_lock(storage_key, fun, opts), to: KeyLock
  defdelegate with_storage_key_locks(storage_keys, fun, opts \\ []), to: KeyLock
  defdelegate wrapper_owned_transaction_lock_held?(storage_key), to: KeyLock
  defdelegate with_session_lock(lock_name, fun), to: KeyLock
  defdelegate with_session_lock(lock_name, fun, opts), to: KeyLock

  @doc "Returns the hard wall-clock deadline shared by UploadPart and cleanup quiescence."
  @spec multipart_upload_part_deadline_ms() :: pos_integer()
  def multipart_upload_part_deadline_ms do
    config =
      Application.get_env(:storyarn, __MODULE__) ||
        Application.fetch_env!(:storyarn, @legacy_config_key)

    case Keyword.fetch!(config, :multipart_upload_part_deadline_ms) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _invalid -> raise "invalid multipart UploadPart deadline"
    end
  end

  defp adapter do
    config = Application.get_env(:storyarn, :storage, [])

    case Keyword.get(config, :adapter, :local) do
      :local -> Local
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
  Summarizes incomplete multipart uploads across the provider namespace or
  beneath one canonical prefix.

  This operation is read-only. It returns no object keys, upload identifiers,
  bucket names, or filenames. A false `inventory_complete` means the bounded
  scan reached its configured limit and must not be treated as proof of an
  empty provider inventory.
  """
  @spec incomplete_multipart_upload_summary(:all | String.t(), keyword()) ::
          {:ok, incomplete_multipart_summary()} | {:error, term()}
  def incomplete_multipart_upload_summary(scope, opts \\ [])

  def incomplete_multipart_upload_summary(scope, opts) when (scope == :all or is_binary(scope)) and is_list(opts) do
    if (scope == :all or canonical_prefix?(scope)) and Keyword.keyword?(opts) do
      adapter = adapter()
      _loaded? = Code.ensure_loaded?(adapter)

      if function_exported?(adapter, :incomplete_multipart_upload_summary, 2),
        do: adapter |> call_multipart_summary(scope, opts) |> normalize_multipart_summary(),
        else: {:error, :multipart_inventory_not_supported}
    else
      {:error, :invalid_multipart_inventory_request}
    end
  end

  def incomplete_multipart_upload_summary(_prefix, _opts), do: {:error, :invalid_multipart_inventory_request}

  defp call_multipart_summary(adapter, scope, opts) do
    adapter.incomplete_multipart_upload_summary(scope, opts)
  rescue
    _exception -> {:error, :multipart_inventory_provider_error}
  catch
    _kind, _reason -> {:error, :multipart_inventory_provider_error}
  end

  defp normalize_multipart_summary({:ok, %{count: count, oldest_initiated_at: oldest, inventory_complete: complete?}})
       when is_integer(count) and count >= 0 and is_boolean(complete?) do
    if is_nil(oldest) or is_struct(oldest, DateTime),
      do: {:ok, %{count: count, oldest_initiated_at: oldest, inventory_complete: complete?}},
      else: {:error, :invalid_multipart_inventory_response}
  end

  defp normalize_multipart_summary({:error, reason})
       when reason in [
              :multipart_inventory_not_supported,
              :invalid_multipart_inventory_request,
              :invalid_multipart_cleanup_limit,
              :invalid_multipart_inventory_limit,
              :invalid_multipart_inventory_response,
              :invalid_multipart_cleanup_response,
              :invalid_multipart_cleanup_cursor,
              :multipart_inventory_provider_error
            ], do: {:error, reason}

  defp normalize_multipart_summary({:error, _provider_reason}), do: {:error, :multipart_inventory_provider_error}

  defp normalize_multipart_summary(_invalid), do: {:error, :invalid_multipart_inventory_response}

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
  Deletes one canonical object key.

  Domain-specific reachability and deletion policy must be enforced by the
  owning context before invoking this technical operation.
  """
  def delete(key) do
    if canonical_key?(key), do: adapter().delete(key), else: {:error, :invalid_key}
  end

  @doc "Deletes an object only when its provider identity still matches."
  def delete_if_matches(key, expected_identity) do
    if canonical_key?(key),
      do: adapter().delete_if_matches(key, expected_identity),
      else: {:error, :invalid_key}
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

  The fallback is intended for immutable consumer-owned namespaces. Callers
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
end
