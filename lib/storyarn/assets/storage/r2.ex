defmodule Storyarn.Assets.Storage.R2 do
  @moduledoc """
  S3-compatible storage adapter for production.

  The module name is historical; this adapter is used for Fly Tigris and other
  S3-compatible providers through ExAws.S3.
  """

  @behaviour Storyarn.Assets.Storage

  @impl true
  def upload(key, data, content_type) do
    bucket = bucket()

    case bucket
         |> ExAws.S3.put_object(key, data, content_type: content_type)
         |> ExAws.request() do
      {:ok, _response} ->
        {:ok, get_url(key)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download(key) do
    case bucket() |> ExAws.S3.get_object(key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    bucket = bucket()

    case bucket |> ExAws.S3.delete_object(key) |> ExAws.request() do
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

    case bucket |> ExAws.S3.put_object_copy(dest_key, bucket, source_key) |> ExAws.request() do
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

  @impl true
  def presigned_download_url(key, opts) do
    bucket = bucket()
    expires_in = Keyword.get(opts, :expires_in, 3600)
    filename = Keyword.get(opts, :filename)
    cache_control = Keyword.get(opts, :cache_control)

    presign_opts = [
      expires_in: expires_in,
      virtual_host: false
    ]

    query_params =
      []
      |> maybe_add_download_filename(filename)
      |> maybe_add_cache_control(cache_control)

    presign_opts =
      if query_params == [],
        do: presign_opts,
        else: Keyword.put(presign_opts, :query_params, query_params)

    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :get, bucket, key, presign_opts) do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def key_from_url(url) when is_binary(url) do
    uri = URI.parse(url)

    with path when is_binary(path) <- uri.path,
         {:ok, key} <- key_from_path(uri, path) do
      {:ok, URI.decode(key)}
    else
      _ -> {:error, :invalid_url}
    end
  end

  def key_from_url(_url), do: {:error, :invalid_url}

  defp maybe_add_download_filename(query_params, nil), do: query_params

  defp maybe_add_download_filename(query_params, filename) do
    disposition = "attachment; filename=\"#{filename}\""
    [{"response-content-disposition", disposition} | query_params]
  end

  defp maybe_add_cache_control(query_params, nil), do: query_params

  defp maybe_add_cache_control(query_params, cache_control) do
    [{"response-cache-control", cache_control} | query_params]
  end

  defp key_from_path(uri, path) do
    endpoint = URI.parse(config()[:endpoint_url] || "")
    public_url = URI.parse(config()[:public_url] || "")

    cond do
      same_origin?(uri, endpoint) ->
        strip_path_prefix(path, "/#{bucket()}/")

      public_url.host && same_origin?(uri, public_url) ->
        public_prefix = String.trim_trailing(public_url.path || "", "/") <> "/"
        strip_path_prefix(path, public_prefix)

      true ->
        {:error, :invalid_url}
    end
  end

  defp same_origin?(%URI{scheme: scheme, host: host, port: port}, %URI{} = expected) do
    scheme == expected.scheme and host == expected.host and port == expected.port
  end

  defp strip_path_prefix(path, prefix) do
    if String.starts_with?(path, prefix) do
      case String.replace_prefix(path, prefix, "") do
        "" -> {:error, :invalid_url}
        key -> {:ok, key}
      end
    else
      {:error, :invalid_url}
    end
  end

  defp bucket do
    config()[:bucket] || raise "object storage bucket not configured"
  end

  defp config do
    Application.get_env(:storyarn, :r2, [])
  end
end
