defmodule Storyarn.Assets.Storage.R2 do
  @moduledoc """
  S3-compatible storage adapter for production.

  The module name is historical; this adapter is used for Fly Tigris and other
  S3-compatible providers through ExAws.S3.
  """

  @behaviour Storyarn.Assets.Storage

  alias Storyarn.Assets.Storage

  @conditional_copy_attempts 3
  @stream_chunk_size 1_048_576
  @multipart_chunk_size 5 * 1024 * 1024

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
  def upload_stream(key, chunks, content_type) do
    with {:ok, upload_id} <- initiate_multipart_upload(key, content_type) do
      case perform_multipart_upload(key, upload_id, chunks) do
        :ok -> {:ok, get_url(key)}
        {:error, reason} -> abort_failed_multipart_upload(key, upload_id, reason)
      end
    end
  end

  defp initiate_multipart_upload(key, content_type) do
    case bucket()
         |> ExAws.S3.initiate_multipart_upload(key, content_type: content_type)
         |> ExAws.request() do
      {:ok, %{body: %{upload_id: upload_id}}} when is_binary(upload_id) and upload_id != "" ->
        {:ok, upload_id}

      {:ok, response} ->
        {:error, {:invalid_multipart_upload_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_multipart_upload(key, upload_id, chunks) do
    with {:ok, parts} <- upload_multipart_parts(key, upload_id, chunks),
         {:ok, _response} <-
           bucket()
           |> ExAws.S3.complete_multipart_upload(key, upload_id, parts)
           |> ExAws.request() do
      :ok
    end
  rescue
    error -> {:error, {:multipart_upload_failed, :error, error}}
  catch
    {:snapshot_stream_error, reason} -> {:error, reason}
    kind, reason -> {:error, {:multipart_upload_failed, kind, reason}}
  end

  defp upload_multipart_parts(key, upload_id, chunks) do
    result =
      chunks
      |> multipart_chunks()
      |> Stream.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {chunk, part_number}, {:ok, parts} ->
        case upload_multipart_part(key, upload_id, part_number, chunk) do
          {:ok, etag} -> {:cont, {:ok, [{part_number, etag} | parts]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, []} ->
        with {:ok, etag} <- upload_multipart_part(key, upload_id, 1, "") do
          {:ok, [{1, etag}]}
        end

      {:ok, parts} ->
        {:ok, Enum.reverse(parts)}

      {:error, _reason} = error ->
        error
    end
  end

  defp upload_multipart_part(key, upload_id, part_number, chunk) do
    case bucket()
         |> ExAws.S3.upload_part(key, upload_id, part_number, chunk)
         |> ExAws.request() do
      {:ok, %{headers: headers}} ->
        case header(headers, "etag") do
          nil -> {:error, {:missing_multipart_etag, part_number}}
          etag -> {:ok, etag}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp abort_failed_multipart_upload(key, upload_id, upload_reason) do
    case bucket()
         |> ExAws.S3.abort_multipart_upload(key, upload_id)
         |> ExAws.request() do
      {:ok, _response} ->
        {:error, upload_reason}

      {:error, abort_reason} ->
        {:error, {:multipart_upload_abort_failed, upload_reason, abort_reason}}
    end
  end

  @impl true
  def put_if_absent(key, data, content_type) do
    request = ExAws.S3.put_object(bucket(), key, data, content_type: content_type, if_none_match: "*")

    case ExAws.request(request) do
      {:ok, _response} -> {:ok, get_url(key), true}
      {:error, {:http_error, 412, _response}} -> {:ok, get_url(key), false}
      {:error, reason} -> {:error, reason}
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
  def list_prefix(prefix, opts) when is_binary(prefix) and is_list(opts) do
    with true <- Storage.canonical_prefix?(prefix) and Keyword.keyword?(opts),
         {:ok, limit} <- list_limit(opts),
         {:ok, request_opts} <- put_continuation_token([prefix: prefix, max_keys: limit], Keyword.get(opts, :cursor)) do
      case bucket() |> ExAws.S3.list_objects_v2(request_opts) |> ExAws.request() do
        {:ok, %{body: body}} when is_map(body) -> normalize_list_page(body, prefix)
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_list_response}
      end
    else
      false -> {:error, :invalid_prefix}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_prefix(_prefix, _opts), do: {:error, :invalid_prefix}

  @impl true
  def delete(key) do
    bucket = bucket()

    case bucket |> ExAws.S3.delete_object(key) |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_if_matches(key, expected_identity)
      when is_binary(expected_identity) and expected_identity != "" and byte_size(expected_identity) <= 1_024 do
    request = ExAws.S3.delete_object(bucket(), key)
    request = %{request | headers: Map.put(request.headers, "if-match", expected_identity)}

    case ExAws.request(request) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 404, _response}} -> :ok
      {:error, {:http_error, 412, _response}} -> {:error, :object_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_if_matches(_key, _expected_identity), do: {:error, :invalid_object_identity}

  @impl true
  def namespace_fingerprint do
    s3_config = Application.get_env(:ex_aws, :s3, [])

    with {:ok, namespace_parts} <-
           normalize_namespace_parts([
             config()[:endpoint_url],
             bucket(),
             Keyword.get(s3_config, :host),
             Keyword.get(s3_config, :scheme)
           ]),
         {:ok, port} <- normalize_namespace_port(Keyword.get(s3_config, :port)) do
      fingerprint =
        ([Atom.to_string(__MODULE__) | namespace_parts] ++ [port])
        |> Jason.encode_to_iodata!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:ok, fingerprint}
    end
  end

  defp normalize_namespace_parts(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, normalized} ->
      case normalize_namespace_part(part) do
        {:ok, value} -> {:cont, {:ok, [value | normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_namespace_part(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :invalid_storage_namespace}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_namespace_part(_value), do: {:error, :invalid_storage_namespace}

  defp normalize_namespace_port(nil), do: {:ok, nil}
  defp normalize_namespace_port(port) when is_integer(port), do: {:ok, port}
  defp normalize_namespace_port(_port), do: {:error, :invalid_storage_namespace}

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
      {:ok, response} -> validate_copy_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def copy_if_absent(source_key, dest_key) do
    request = conditional_copy_request(source_key, dest_key)
    execute_conditional_copy(request, @conditional_copy_attempts)
  end

  defp execute_conditional_copy(request, attempts_left) do
    case ExAws.request(request) do
      {:ok, response} ->
        case validate_copy_response(response) do
          :ok -> {:ok, true}
          {:error, reason} -> {:error, reason}
        end

      {:error, {:http_error, 412, _response}} ->
        {:ok, false}

      {:error, {:http_error, 409, _response}} when attempts_left > 1 ->
        execute_conditional_copy(request, attempts_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_copy_response(%{body: body}) when is_binary(body) do
    cond do
      String.contains?(body, "<Error") -> {:error, :copy_object_error_response}
      String.contains?(body, "<CopyObjectResult") -> :ok
      true -> {:error, :invalid_copy_object_response}
    end
  end

  defp validate_copy_response(_response), do: {:error, :invalid_copy_object_response}

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

  defp multipart_chunks(chunks) do
    Stream.transform(
      chunks,
      fn -> {[], 0} end,
      fn
        {:ok, chunk}, {buffer, size} when is_binary(chunk) ->
          new_buffer = [buffer, chunk]
          new_size = size + byte_size(chunk)

          if new_size >= @multipart_chunk_size do
            {[IO.iodata_to_binary(new_buffer)], {[], 0}}
          else
            {[], {new_buffer, new_size}}
          end

        {:error, reason}, _state ->
          throw({:snapshot_stream_error, reason})

        _unexpected, _state ->
          throw({:snapshot_stream_error, :unexpected_blob_stream_chunk})
      end,
      fn
        {[], 0} = state -> {[], state}
        {buffer, _size} -> {[IO.iodata_to_binary(buffer)], {[], 0}}
      end,
      fn _state -> :ok end
    )
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

  defp conditional_copy_request(source_key, dest_key) do
    bucket = bucket()
    request = ExAws.S3.put_object_copy(bucket, dest_key, bucket, source_key, if_none_match: "*")

    if cloudflare_r2_endpoint?() do
      %{request | headers: Map.put(request.headers, "cf-copy-destination-if-none-match", "*")}
    else
      request
    end
  end

  defp put_continuation_token(opts, nil), do: {:ok, opts}

  defp put_continuation_token(opts, token) when is_binary(token) and token != "",
    do: {:ok, Keyword.put(opts, :continuation_token, token)}

  defp put_continuation_token(_opts, _invalid), do: {:error, :invalid_cursor}

  defp list_limit(opts) do
    case Keyword.get(opts, :limit, 1_000) do
      limit when is_integer(limit) and limit > 0 -> {:ok, min(limit, 1_000)}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp normalize_list_page(body, prefix) do
    contents = Map.get(body, :contents, Map.get(body, "Contents", [])) || []
    is_truncated = Map.get(body, :is_truncated, Map.get(body, "IsTruncated"))
    continuation_token = Map.get(body, :next_continuation_token, Map.get(body, "NextContinuationToken"))

    with true <- is_list(contents),
         {:ok, objects} <- normalize_list_objects(contents, prefix),
         {:ok, truncated?} <- normalize_is_truncated(is_truncated),
         {:ok, cursor} <- normalize_list_cursor(continuation_token, truncated?) do
      {:ok, %{objects: objects, cursor: cursor}}
    else
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp normalize_list_objects(contents, prefix) do
    contents
    |> Enum.reduce_while({:ok, []}, fn object, {:ok, objects} ->
      with true <- is_map(object),
           key when is_binary(key) <- Map.get(object, :key, Map.get(object, "Key")),
           true <- Storage.canonical_key?(key) and String.starts_with?(key, prefix),
           {:ok, size} <- normalize_list_size(Map.get(object, :size, Map.get(object, "Size"))),
           {:ok, identity} <- normalize_object_identity(object) do
        {:cont, {:ok, [%{key: key, size: size, identity: identity} | objects]}}
      else
        _invalid -> {:halt, {:error, :invalid_list_response}}
      end
    end)
    |> case do
      {:ok, objects} -> {:ok, Enum.reverse(objects)}
      error -> error
    end
  end

  defp normalize_list_size(size) when is_integer(size) and size >= 0, do: {:ok, size}

  defp normalize_list_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp normalize_list_size(_size), do: {:error, :invalid_list_response}

  defp normalize_object_identity(object) do
    identity =
      Map.get(
        object,
        :e_tag,
        Map.get(object, :etag, Map.get(object, "ETag"))
      )

    if is_binary(identity) and identity != "" and byte_size(identity) <= 1_024,
      do: {:ok, identity},
      else: {:error, :invalid_list_response}
  end

  defp normalize_is_truncated(value) when value in [true, "true"], do: {:ok, true}
  defp normalize_is_truncated(value) when value in [false, "false"], do: {:ok, false}
  defp normalize_is_truncated(_value), do: {:error, :invalid_list_response}

  defp normalize_list_cursor(cursor, true) when is_binary(cursor) and cursor != "" and byte_size(cursor) <= 4_096,
    do: {:ok, cursor}

  defp normalize_list_cursor(cursor, false) when cursor in [nil, ""], do: {:ok, nil}
  defp normalize_list_cursor(_cursor, _truncated?), do: {:error, :invalid_list_response}

  defp cloudflare_r2_endpoint? do
    case URI.parse(config()[:endpoint_url] || "").host do
      host when is_binary(host) ->
        host = String.downcase(host)
        host == "r2.cloudflarestorage.com" or String.ends_with?(host, ".r2.cloudflarestorage.com")

      _host ->
        false
    end
  end

  defp bucket do
    config()[:bucket] || raise "object storage bucket not configured"
  end

  defp config do
    Application.get_env(:storyarn, :r2, [])
  end
end
