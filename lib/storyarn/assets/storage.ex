defmodule Storyarn.Assets.Storage do
  @moduledoc """
  Behaviour for asset storage backends.

  Supports both local file storage (development) and Cloudflare R2 (production).
  """

  @type key :: String.t()
  @type url :: String.t()
  @type content_type :: String.t()
  @type binary_data :: binary()

  @callback upload(key, binary_data, content_type) :: {:ok, url} | {:error, term()}
  @callback delete(key) :: :ok | {:error, term()}
  @callback get_url(key) :: url
  @callback presigned_upload_url(key, content_type, opts :: keyword()) ::
              {:ok, url, map()} | {:error, term()}

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
  Deletes a file from storage.
  """
  def delete(key) do
    adapter().delete(key)
  end

  @doc """
  Gets the public URL for a file.
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
end
