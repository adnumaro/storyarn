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

  @callback upload(key, binary_data, content_type) :: {:ok, url} | {:error, term()}
  @callback put_if_absent(key, binary_data, content_type) ::
              {:ok, url, created? :: boolean()} | {:error, term()}
  @callback delete(key) :: :ok | {:error, term()}
  @callback get_url(key) :: url
  @callback download(key) :: {:ok, binary_data} | {:error, term()}
  @callback stat(key) :: {:ok, object_stat} | {:error, term()}
  @callback stream(key, non_neg_integer(), non_neg_integer(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback presigned_upload_url(key, content_type, opts :: keyword()) ::
              {:ok, url, map()} | {:error, term()}
  @callback copy(source_key :: key, dest_key :: key) :: :ok | {:error, term()}
  @callback key_from_url(url) :: {:ok, key} | {:error, :invalid_url}

  @doc """
  Returns the configured storage adapter.
  """
  def adapter do
    config = Application.get_env(:storyarn, :storage, [])

    case Keyword.get(config, :adapter, :local) do
      :local -> Storyarn.Assets.Storage.Local
      :r2 -> Storyarn.Assets.Storage.R2
    end
  end

  @doc """
  Uploads a file to storage.
  """
  def upload(key, data, content_type) do
    adapter().upload(key, data, content_type)
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

  defp canonical_key?(key) when is_binary(key) do
    key != "" and
      String.valid?(key) and
      not String.contains?(key, [<<0>>, "\\"]) and
      canonical_segments?(String.split(key, "/", trim: false))
  end

  defp canonical_key?(_key), do: false

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
