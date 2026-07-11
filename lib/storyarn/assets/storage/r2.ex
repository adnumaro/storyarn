defmodule Storyarn.Assets.Storage.R2 do
  @moduledoc """
  S3-compatible storage adapter for production.

  The module name is historical; this adapter is used for Fly Tigris and other
  S3-compatible providers through ExAws.S3.
  """

  @behaviour Storyarn.Assets.Storage

  @stream_chunk_size 1_048_576

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
  def stat(key) do
    case bucket() |> ExAws.S3.head_object(key) |> ExAws.request() do
      {:ok, %{headers: headers}} ->
        with {:ok, size} <- integer_header(headers, "content-length") do
          {:ok,
           %{
             size: size,
             etag: header(headers, "etag"),
             content_type: header(headers, "content-type")
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream(key, offset, length, opts) when is_integer(offset) and offset >= 0 and is_integer(length) and length >= 0 do
    etag = Keyword.get(opts, :etag)
    {:ok, range_stream(key, offset, length, etag)}
  end

  def stream(_key, _offset, _length, _opts), do: {:error, :invalid_range}

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

  defp range_stream(_key, _offset, 0, _etag), do: []

  defp range_stream(key, offset, length, etag) do
    {offset, length}
    |> Stream.unfold(fn
      {_offset, 0} ->
        nil

      {chunk_offset, remaining} ->
        chunk_length = min(remaining, @stream_chunk_size)
        last_byte = chunk_offset + chunk_length - 1
        bounds = {chunk_offset, last_byte, chunk_length}
        {bounds, {last_byte + 1, remaining - chunk_length}}
    end)
    |> Stream.map(fn {first_byte, last_byte, expected_length} ->
      download_range(key, first_byte, last_byte, expected_length, etag)
    end)
  end

  defp download_range(key, first_byte, last_byte, expected_length, etag) do
    request_opts = maybe_put_if_match([range: "bytes=#{first_byte}-#{last_byte}"], etag)

    case bucket() |> ExAws.S3.get_object(key, request_opts) |> ExAws.request() do
      {:ok, %{body: body}} when byte_size(body) == expected_length ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, {:unexpected_length, byte_size(body), expected_length}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_if_match(opts, nil), do: opts
  defp maybe_put_if_match(opts, etag), do: Keyword.put(opts, :if_match, etag)

  defp integer_header(headers, name) do
    case header(headers, name) do
      nil ->
        {:error, {:missing_header, name}}

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> {:error, {:invalid_header, name}}
        end
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {header_name, value} ->
      if String.downcase(to_string(header_name)) == name do
        value |> List.wrap() |> List.first() |> to_string()
      end
    end)
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
