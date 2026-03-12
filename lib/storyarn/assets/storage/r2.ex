defmodule Storyarn.Assets.Storage.R2 do
  @moduledoc """
  Cloudflare R2 storage adapter for production.

  R2 is S3-compatible, so we use the ExAws.S3 library.
  """

  @behaviour Storyarn.Assets.Storage

  @impl true
  def upload(key, data, content_type) do
    bucket = bucket()

    case ExAws.S3.put_object(bucket, key, data, content_type: content_type)
         |> ExAws.request() do
      {:ok, _response} ->
        {:ok, get_url(key)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download(key) do
    case ExAws.S3.get_object(bucket(), key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    bucket = bucket()

    case ExAws.S3.delete_object(bucket, key) |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_url(key) do
    case config()[:public_url] do
      nil ->
        # Fallback to constructing URL from endpoint
        endpoint = config()[:endpoint_url]
        bucket = bucket()
        "#{endpoint}/#{bucket}/#{key}"

      public_url ->
        "#{public_url}/#{key}"
    end
  end

  @impl true
  def copy(source_key, dest_key) do
    bucket = bucket()

    case ExAws.S3.put_object_copy(bucket, dest_key, bucket, source_key) |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def presigned_upload_url(key, content_type, opts) do
    bucket = bucket()
    expires_in = Keyword.get(opts, :expires_in, 3600)

    presign_opts = [
      expires_in: expires_in,
      virtual_host: false,
      query_params: [{"Content-Type", content_type}]
    ]

    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :put, bucket, key, presign_opts) do
      {:ok, url} ->
        {:ok, url, %{content_type: content_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bucket do
    config()[:bucket] || raise "R2_BUCKET not configured"
  end

  defp config do
    Application.get_env(:storyarn, :r2, [])
  end
end
