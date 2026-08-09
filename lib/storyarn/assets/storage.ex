defmodule Storyarn.Assets.Storage do
  @moduledoc """
  Behaviour for asset storage backends.

  Supports both local file storage (development) and S3-compatible storage (production).
  """

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
  @callback copy(source_key :: key, dest_key :: key) :: :ok | {:error, term()}
  @callback copy_if_absent(source_key :: key, dest_key :: key) ::
              {:ok, created? :: boolean()} | {:error, term()}
  @callback key_from_url(url) :: {:ok, key} | {:error, :invalid_url}
  @callback list_prefix(String.t(), keyword()) :: {:ok, list_page()} | {:error, term()}
  @callback list_prefix_metadata(String.t(), keyword()) :: {:ok, metadata_list_page()} | {:error, term()}
  @optional_callbacks list_prefix_metadata: 2

  @doc """
  Returns the configured storage adapter.
  """
  def adapter do
    config = Application.get_env(:storyarn, :storage, [])

    case Keyword.get(config, :adapter, :local) do
      :local -> Storyarn.Assets.Storage.Local
      :r2 -> Storyarn.Assets.Storage.R2
      adapter when is_atom(adapter) -> adapter
    end
  end

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
