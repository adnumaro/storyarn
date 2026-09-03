defmodule Storyarn.Platform.ObjectStorage.Adapters.R2 do
  @moduledoc """
  S3-compatible storage adapter for production.

  The module name is historical; this adapter is used for Fly Tigris and other
  S3-compatible providers through ExAws.S3.
  """

  @behaviour Storyarn.Platform.ObjectStorage

  import SweetXml, only: [sigil_x: 2]

  alias Storyarn.Platform.ObjectStorage, as: Storage

  @conditional_copy_attempts 3
  @stream_chunk_size 1_048_576
  @multipart_chunk_size 5 * 1024 * 1024
  @multipart_cleanup_page_size 100
  @multipart_cleanup_batch_size 100
  @multipart_cleanup_max_uploads 10_000
  @multipart_inventory_max_pages 100
  @multipart_inventory_max_response_bytes 2 * 1024 * 1024

  # This value is part of the persisted cleanup and reconciliation contract.
  # Keep the pre-Projects namespace so moving this adapter cannot strand work
  # that was captured by an older release.
  @namespace_identity "Elixir.Storyarn.Assets.Storage.R2"

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
    with {:ok, parts} <- upload_multipart_parts(key, upload_id, chunks) do
      complete_multipart_upload(key, upload_id, parts)
    end
  rescue
    error -> {:error, {:multipart_upload_failed, :error, error}}
  catch
    {:object_stream_error, reason} -> {:error, reason}
    kind, reason -> {:error, {:multipart_upload_failed, kind, reason}}
  end

  defp complete_multipart_upload(key, upload_id, parts) do
    case bucket()
         |> ExAws.S3.complete_multipart_upload(key, upload_id, parts)
         |> ExAws.request() do
      {:ok, response} -> validate_multipart_completion(response, key)
      {:error, reason} -> {:error, reason}
    end
  rescue
    Protocol.UndefinedError -> {:error, :invalid_multipart_upload_completion_response}
  end

  defp validate_multipart_completion(%{body: %{key: key, etag: etag}}, key) when is_binary(etag) and etag != "", do: :ok

  defp validate_multipart_completion(_response, _key), do: {:error, :invalid_multipart_upload_completion_response}

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
    request = ExAws.S3.upload_part(bucket(), key, upload_id, part_number, chunk)

    case request_upload_part(request) do
      {:ok, %{headers: headers}} ->
        case header(headers, "etag") do
          nil -> {:error, {:missing_multipart_etag, part_number}}
          etag -> {:ok, etag}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_upload_part(request) do
    request_with_deadline(
      request,
      Storage.write_operation_deadline(),
      :multipart_upload_part_timeout,
      :multipart_upload_part_task_exit
    )
  end

  defp request_with_deadline(request, deadline, timeout_error, task_exit_error) do
    remaining_ms = deadline - System.monotonic_time(:millisecond)

    if remaining_ms > 0 do
      task = Task.async(fn -> run_multipart_request(request) end)

      task
      |> Task.yield(remaining_ms)
      |> resolve_multipart_request_yield(task, timeout_error, task_exit_error)
    else
      {:error, timeout_error}
    end
  end

  defp run_multipart_request(request) do
    {:request_result, ExAws.request(request)}
  rescue
    _exception -> {:request_failed, :exception}
  catch
    kind, _reason -> {:request_failed, kind}
  end

  defp resolve_multipart_request_yield({:ok, result}, _task, _timeout_error, task_exit_error),
    do: normalize_multipart_request_result(result, task_exit_error)

  defp resolve_multipart_request_yield({:exit, _reason}, _task, _timeout_error, task_exit_error),
    do: {:error, task_exit_error}

  defp resolve_multipart_request_yield(nil, task, timeout_error, task_exit_error) do
    task
    |> Task.shutdown(:brutal_kill)
    |> normalize_multipart_request_shutdown(timeout_error, task_exit_error)
  end

  defp normalize_multipart_request_result({:request_result, result}, _task_exit_error), do: result

  defp normalize_multipart_request_result({:request_failed, _kind}, task_exit_error), do: {:error, task_exit_error}

  defp normalize_multipart_request_shutdown({:ok, result}, _timeout_error, task_exit_error),
    do: normalize_multipart_request_result(result, task_exit_error)

  defp normalize_multipart_request_shutdown({:exit, _reason}, _timeout_error, task_exit_error),
    do: {:error, task_exit_error}

  defp normalize_multipart_request_shutdown(nil, timeout_error, _task_exit_error), do: {:error, timeout_error}

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
  def abort_incomplete_multipart_uploads(key, opts) do
    with {:ok, max_uploads} <- multipart_cleanup_limit(opts),
         {:ok, max_passes} <- multipart_cleanup_pass_limit(opts) do
      abort_until_multipart_inventory_empty(key, max_uploads, max_passes, 0)
    end
  end

  @impl true
  def list_incomplete_multipart_uploads(key, opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, batch_size} <- multipart_cleanup_batch_limit(opts),
         {:ok, page} <- list_multipart_upload_page(key, nil, batch_size),
         :ok <- validate_multipart_page(page, batch_size),
         {:ok, uploads} <- exact_multipart_uploads(page.uploads, key) do
      {:ok,
       %{
         uploads: Enum.map(uploads, fn {upload_key, upload_id} -> %{key: upload_key, upload_id: upload_id} end),
         inventory_complete: exact_multipart_inventory_complete?(page, key)
       }}
    else
      false -> {:error, :invalid_multipart_inventory_request}
      {:error, _reason} = error -> error
    end
  rescue
    _exception -> {:error, :multipart_inventory_provider_error}
  catch
    _kind, _reason -> {:error, :multipart_inventory_provider_error}
  end

  @impl true
  def abort_incomplete_multipart_upload(key, upload_id) do
    case do_abort_multipart_upload(key, upload_id) do
      :ok -> :ok
      {:error, _provider_reason} -> {:error, :multipart_cleanup_provider_error}
    end
  rescue
    _exception -> {:error, :multipart_cleanup_provider_error}
  catch
    _kind, _reason -> {:error, :multipart_cleanup_provider_error}
  end

  @impl true
  def incomplete_multipart_upload_state(key, upload_id) do
    multipart_upload_reference_state(key, upload_id)
  rescue
    _exception -> {:error, :multipart_inventory_provider_error}
  catch
    _kind, _reason -> {:error, :multipart_inventory_provider_error}
  end

  @impl true
  def incomplete_multipart_upload_count(key, opts) do
    with {:ok, max_uploads} <- multipart_cleanup_limit(opts),
         {:ok, uploads} <- list_exact_multipart_uploads(key, max_uploads) do
      {:ok, length(uploads)}
    end
  end

  @impl true
  def incomplete_multipart_upload_summary(scope, opts) do
    with true <- valid_multipart_inventory_scope?(scope) and Keyword.keyword?(opts),
         {:ok, max_uploads} <- multipart_cleanup_limit(opts),
         {:ok, max_pages} <- multipart_inventory_page_limit(opts) do
      summarize_incomplete_multipart_uploads(
        scope,
        nil,
        max_uploads,
        max_pages,
        0,
        nil,
        MapSet.new()
      )
    else
      false -> {:error, :invalid_multipart_inventory_request}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _exception -> {:error, :multipart_inventory_provider_error}
  catch
    _kind, _reason -> {:error, :multipart_inventory_provider_error}
  end

  defp multipart_cleanup_limit(opts) do
    case Keyword.get(opts, :max_uploads, @multipart_cleanup_max_uploads) do
      limit when is_integer(limit) and limit > 0 ->
        {:ok, min(limit, @multipart_cleanup_max_uploads)}

      _invalid ->
        {:error, :invalid_multipart_cleanup_limit}
    end
  end

  defp multipart_cleanup_pass_limit(opts) do
    case Keyword.get(opts, :max_passes, 3) do
      passes when is_integer(passes) and passes > 0 and passes <= 10 -> {:ok, passes}
      _invalid -> {:error, :invalid_multipart_cleanup_pass_limit}
    end
  end

  defp multipart_cleanup_batch_limit(opts) do
    case Keyword.get(opts, :batch_size, @multipart_cleanup_batch_size) do
      batch_size when is_integer(batch_size) and batch_size > 0 and batch_size <= @multipart_cleanup_batch_size ->
        {:ok, batch_size}

      _invalid ->
        {:error, :invalid_multipart_cleanup_batch_limit}
    end
  end

  defp multipart_inventory_page_limit(opts) do
    case Keyword.get(opts, :max_pages, @multipart_inventory_max_pages) do
      pages when is_integer(pages) and pages > 0 ->
        {:ok, min(pages, @multipart_inventory_max_pages)}

      _invalid ->
        {:error, :invalid_multipart_inventory_limit}
    end
  end

  defp abort_until_multipart_inventory_empty(key, max_uploads, remaining_passes, aborted_count) do
    with {:ok, uploads} <- list_exact_multipart_uploads(key, max_uploads) do
      abort_multipart_inventory(key, uploads, max_uploads, remaining_passes, aborted_count)
    end
  end

  defp abort_multipart_inventory(_key, [], _max_uploads, _remaining_passes, aborted_count), do: {:ok, aborted_count}

  defp abort_multipart_inventory(key, uploads, max_uploads, remaining_passes, aborted_count) when remaining_passes > 0 do
    with :ok <- abort_multipart_uploads(uploads, remaining_passes) do
      abort_until_multipart_inventory_empty(
        key,
        max_uploads,
        remaining_passes - 1,
        aborted_count + length(uploads)
      )
    end
  end

  defp abort_multipart_inventory(_key, _uploads, _max_uploads, 0, _aborted_count),
    do: {:error, :multipart_cleanup_not_quiescent}

  defp list_exact_multipart_uploads(key, max_uploads) do
    do_list_exact_multipart_uploads(key, nil, max_uploads, [], MapSet.new())
  end

  defp do_list_exact_multipart_uploads(key, cursor, remaining, uploads, seen_cursors) do
    page_limit = min(remaining, @multipart_cleanup_page_size)

    with {:ok, page} <- list_multipart_upload_page(key, cursor, page_limit),
         :ok <- validate_multipart_page(page, page_limit),
         {:ok, exact_uploads} <- exact_multipart_uploads(page.uploads, key),
         {:ok, next} <- multipart_page_continuation(page, cursor, seen_cursors) do
      collected = uploads ++ exact_uploads
      consumed = length(page.uploads)

      case next do
        nil ->
          {:ok, collected}

        next_cursor when consumed < remaining ->
          do_list_exact_multipart_uploads(
            key,
            next_cursor,
            remaining - consumed,
            collected,
            MapSet.put(seen_cursors, next_cursor)
          )

        _next_cursor ->
          {:error, :multipart_cleanup_inventory_limit_exceeded}
      end
    end
  end

  defp list_multipart_upload_page(scope, cursor, limit, encoding \\ :identity) do
    opts =
      [max_uploads: limit]
      |> maybe_put_multipart_encoding(encoding)
      |> maybe_put_multipart_prefix(scope)
      |> maybe_put_multipart_cursor(cursor)

    request =
      bucket()
      |> ExAws.S3.list_multipart_uploads(opts)
      |> Map.put(:parser, &parse_multipart_upload_page/1)

    case request_with_deadline(
           request,
           Storage.write_operation_deadline(),
           :multipart_inventory_timeout,
           :multipart_inventory_task_exit
         ) do
      {:ok, %{body: page}} when is_map(page) ->
        normalize_multipart_page_encoding(page, encoding)

      {:ok, _invalid} ->
        {:error, :invalid_multipart_cleanup_response}

      {:error, reason}
      when reason in [
             :invalid_multipart_cleanup_response,
             :invalid_multipart_inventory_response
           ] ->
        {:error, reason}

      {:error, _provider_reason} ->
        {:error, :multipart_inventory_provider_error}
    end
  end

  defp maybe_put_multipart_cursor(opts, nil), do: opts

  defp maybe_put_multipart_cursor(opts, {key_marker, upload_id_marker}) do
    opts
    |> Keyword.put(:key_marker, key_marker)
    |> Keyword.put(:upload_id_marker, upload_id_marker)
  end

  defp maybe_put_multipart_prefix(opts, :all), do: opts
  defp maybe_put_multipart_prefix(opts, prefix), do: Keyword.put(opts, :prefix, prefix)

  defp maybe_put_multipart_encoding(opts, :identity), do: opts
  defp maybe_put_multipart_encoding(opts, :url), do: Keyword.put(opts, :encoding_type, "url")

  defp parse_multipart_upload_page({:ok, %{body: xml} = response})
       when is_binary(xml) and byte_size(xml) <= @multipart_inventory_max_response_bytes do
    page =
      SweetXml.xpath(xml, ~x"//ListMultipartUploadsResult",
        encoding_type: ~x"./EncodingType/text()"s,
        is_truncated: ~x"./IsTruncated/text()"s,
        next_key_marker: ~x"./NextKeyMarker/text()"s,
        next_upload_id_marker: ~x"./NextUploadIdMarker/text()"s,
        uploads: [
          ~x"./Upload"l,
          key: ~x"./Key/text()"s,
          upload_id: ~x"./UploadId/text()"s,
          initiated_at: ~x"./Initiated/text()"s
        ]
      )

    {:ok, %{response | body: page}}
  end

  defp parse_multipart_upload_page({:ok, %{body: xml}}) when is_binary(xml),
    do: {:error, :invalid_multipart_cleanup_response}

  defp parse_multipart_upload_page(result), do: result

  defp normalize_multipart_page_encoding(page, :identity), do: {:ok, page}

  defp normalize_multipart_page_encoding(%{encoding_type: "url", uploads: uploads} = page, :url) when is_list(uploads) do
    with {:ok, next_key_marker} <- decode_multipart_key(Map.get(page, :next_key_marker, "")),
         {:ok, uploads} <- decode_multipart_upload_keys(uploads) do
      {:ok, %{page | next_key_marker: next_key_marker, uploads: uploads}}
    end
  end

  defp normalize_multipart_page_encoding(_page, :url), do: {:error, :invalid_multipart_inventory_response}

  defp decode_multipart_upload_keys(uploads) do
    uploads
    |> Enum.reduce_while({:ok, []}, fn
      %{key: encoded_key} = upload, {:ok, decoded} ->
        case decode_multipart_key(encoded_key) do
          {:ok, ""} -> {:halt, {:error, :invalid_multipart_inventory_response}}
          {:ok, key} -> {:cont, {:ok, [%{upload | key: key} | decoded]}}
          {:error, _reason} = error -> {:halt, error}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_multipart_inventory_response}}
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_multipart_key(value) when is_binary(value) do
    if valid_url_encoding?(value) do
      decoded = URI.decode(value)

      if String.valid?(decoded),
        do: {:ok, decoded},
        else: {:error, :invalid_multipart_inventory_response}
    else
      {:error, :invalid_multipart_inventory_response}
    end
  end

  defp decode_multipart_key(_value), do: {:error, :invalid_multipart_inventory_response}

  defp validate_multipart_page(%{uploads: uploads, is_truncated: truncated}, page_limit)
       when is_list(uploads) and length(uploads) <= page_limit and truncated in ["true", "false"] do
    if truncated == "false" or uploads != [],
      do: :ok,
      else: {:error, :invalid_multipart_cleanup_response}
  end

  defp validate_multipart_page(_page, _page_limit), do: {:error, :invalid_multipart_cleanup_response}

  defp summarize_incomplete_multipart_uploads(
         scope,
         cursor,
         remaining_uploads,
         remaining_pages,
         count,
         oldest,
         seen_cursors
       ) do
    page_limit = min(remaining_uploads, @multipart_cleanup_page_size)

    with {:ok, page} <- list_multipart_upload_page(scope, cursor, page_limit, :url),
         :ok <- validate_multipart_page(page, page_limit),
         {:ok, page_oldest} <- oldest_multipart_initiated_at(page.uploads, scope),
         {:ok, next} <- multipart_page_continuation(page, cursor, seen_cursors) do
      next_count = count + length(page.uploads)
      next_oldest = oldest_datetime(oldest, page_oldest)
      consumed = length(page.uploads)

      cond do
        is_nil(next) ->
          {:ok,
           %{
             count: next_count,
             oldest_initiated_at: next_oldest,
             inventory_complete: true
           }}

        consumed < remaining_uploads and remaining_pages > 1 ->
          summarize_incomplete_multipart_uploads(
            scope,
            next,
            remaining_uploads - consumed,
            remaining_pages - 1,
            next_count,
            next_oldest,
            MapSet.put(seen_cursors, next)
          )

        true ->
          {:ok,
           %{
             count: next_count,
             oldest_initiated_at: next_oldest,
             inventory_complete: false
           }}
      end
    end
  end

  defp oldest_multipart_initiated_at(uploads, scope) do
    Enum.reduce_while(uploads, {:ok, nil}, fn
      %{key: key, initiated_at: initiated_at}, {:ok, oldest}
      when is_binary(key) and is_binary(initiated_at) ->
        with true <- multipart_upload_in_scope?(key, scope),
             {:ok, parsed} <- parse_multipart_initiated_at(initiated_at) do
          {:cont, {:ok, oldest_datetime(oldest, parsed)}}
        else
          _invalid -> {:halt, {:error, :invalid_multipart_inventory_response}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_multipart_inventory_response}}
    end)
  end

  defp parse_multipart_initiated_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, initiated_at, _offset} -> {:ok, DateTime.truncate(initiated_at, :second)}
      {:error, _reason} -> {:error, :invalid_multipart_inventory_response}
    end
  end

  defp valid_multipart_inventory_scope?(:all), do: true
  defp valid_multipart_inventory_scope?(prefix), do: Storage.canonical_prefix?(prefix)

  defp multipart_upload_in_scope?(key, :all), do: is_binary(key)
  defp multipart_upload_in_scope?(key, prefix), do: is_binary(key) and String.starts_with?(key, prefix)

  defp oldest_datetime(nil, value), do: value
  defp oldest_datetime(value, nil), do: value

  defp oldest_datetime(left, right) do
    if DateTime.after?(left, right), do: right, else: left
  end

  defp exact_multipart_uploads(uploads, key) do
    uploads
    |> Enum.reduce_while({:ok, []}, fn
      %{key: upload_key, upload_id: upload_id}, {:ok, exact}
      when is_binary(upload_key) and is_binary(upload_id) and upload_id != "" ->
        cond do
          upload_key == key ->
            {:cont, {:ok, [{upload_key, upload_id} | exact]}}

          String.starts_with?(upload_key, key) ->
            {:cont, {:ok, exact}}

          true ->
            {:halt, {:error, :invalid_multipart_cleanup_response}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_multipart_cleanup_response}}
    end)
    |> case do
      {:ok, exact} -> {:ok, Enum.reverse(exact)}
      {:error, _reason} = error -> error
    end
  end

  # ListMultipartUploads is ordered by key and then upload id. Once a page has
  # crossed the exact requested key, later truncated pages can contain only
  # sibling keys and do not keep this exact-key inventory open forever.
  defp exact_multipart_inventory_complete?(%{is_truncated: "false"}, _key), do: true

  defp exact_multipart_inventory_complete?(%{uploads: uploads}, key) do
    Enum.any?(uploads, fn
      %{key: upload_key} when is_binary(upload_key) -> upload_key > key
      _invalid -> false
    end)
  end

  defp multipart_page_continuation(%{is_truncated: "false"}, _cursor, _seen), do: {:ok, nil}

  defp multipart_page_continuation(
         %{is_truncated: "true", next_key_marker: key_marker, next_upload_id_marker: upload_id_marker},
         cursor,
         seen
       )
       when is_binary(key_marker) and key_marker != "" and is_binary(upload_id_marker) and upload_id_marker != "" do
    next = {key_marker, upload_id_marker}

    if next != cursor and not MapSet.member?(seen, next),
      do: {:ok, next},
      else: {:error, :invalid_multipart_cleanup_cursor}
  end

  defp multipart_page_continuation(_page, _cursor, _seen), do: {:error, :invalid_multipart_cleanup_cursor}

  defp abort_multipart_uploads(uploads, max_passes) do
    Enum.reduce_while(uploads, :ok, fn {key, upload_id}, :ok ->
      case abort_multipart_upload_until_empty(key, upload_id, max_passes) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp abort_multipart_upload_until_empty(_key, _upload_id, 0), do: {:error, :multipart_cleanup_not_quiescent}

  defp abort_multipart_upload_until_empty(key, upload_id, remaining_passes) do
    with :ok <- do_abort_multipart_upload(key, upload_id),
         {:ok, parts_state} <- multipart_upload_parts_state(key, upload_id) do
      case parts_state do
        :empty -> :ok
        :present -> abort_multipart_upload_until_empty(key, upload_id, remaining_passes - 1)
      end
    end
  end

  defp do_abort_multipart_upload(key, upload_id) do
    request = ExAws.S3.abort_multipart_upload(bucket(), key, upload_id)

    case request_with_deadline(
           request,
           Storage.write_operation_deadline(),
           :multipart_cleanup_abort_timeout,
           :multipart_cleanup_abort_task_exit
         ) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 404, _response}} -> :ok
      {:error, reason} -> {:error, {:multipart_cleanup_abort_failed, reason}}
    end
  end

  defp multipart_upload_reference_state(key, upload_id) do
    request = ExAws.S3.list_parts(bucket(), key, upload_id, max_parts: 1)

    case request_with_deadline(
           request,
           Storage.write_operation_deadline(),
           :multipart_inventory_provider_error,
           :multipart_inventory_provider_error
         ) do
      {:ok, %{body: %{parts: parts}}} when is_list(parts) -> {:ok, :present}
      {:error, {:http_error, 404, _response}} -> {:ok, :absent_now}
      {:ok, _invalid} -> {:error, :invalid_multipart_parts_response}
      {:error, _reason} -> {:error, :multipart_inventory_provider_error}
    end
  end

  defp multipart_upload_parts_state(key, upload_id) do
    case multipart_upload_reference_state(key, upload_id) do
      {:ok, :absent_now} -> {:ok, :empty}
      {:ok, :present} -> {:ok, :present}
      {:error, _reason} = error -> error
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
  def object_probe(key) do
    case head_object_metadata(key) do
      {:ok, %{size: size, etag: identity, content_type: content_type}}
      when is_binary(identity) and identity != "" and is_binary(content_type) and content_type != "" ->
        {:ok, %{size: size, identity: identity, content_type: content_type}}

      {:ok, _metadata} ->
        {:error, :invalid_object_probe_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp head_object_metadata(key) do
    request = ExAws.S3.head_object(bucket(), key)

    case request_with_deadline(
           request,
           Storage.write_operation_deadline(),
           :object_stat_timeout,
           :object_stat_task_exit
         ) do
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
    list_prefix_page(prefix, opts, :identity)
  end

  def list_prefix(_prefix, _opts), do: {:error, :invalid_prefix}

  @impl true
  def list_prefix_metadata(prefix, opts) when is_binary(prefix) and is_list(opts) do
    list_prefix_page(prefix, opts, :metadata)
  end

  def list_prefix_metadata(_prefix, _opts), do: {:error, :invalid_prefix}

  defp list_prefix_page(prefix, opts, mode) do
    with true <- Storage.canonical_prefix?(prefix) and Keyword.keyword?(opts),
         {:ok, limit} <- list_limit(opts),
         {:ok, request_opts} <-
           put_continuation_token(
             [prefix: prefix, max_keys: limit, encoding_type: "url"],
             Keyword.get(opts, :cursor)
           ) do
      case bucket() |> ExAws.S3.list_objects_v2(request_opts) |> ExAws.request() do
        {:ok, %{body: body}} when is_map(body) -> normalize_list_page(body, prefix, mode)
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_list_response}
      end
    else
      false -> {:error, :invalid_prefix}
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
  def delete_if_matches(key, expected_identity)
      when is_binary(expected_identity) and expected_identity != "" and byte_size(expected_identity) <= 1_024 do
    request = ExAws.S3.delete_object(bucket(), key)
    request = %{request | headers: Map.put(request.headers, "if-match", expected_identity)}

    case request_with_deadline(
           request,
           Storage.write_operation_deadline(),
           :conditional_delete_timeout,
           :conditional_delete_task_exit
         ) do
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
        ([@namespace_identity | namespace_parts] ++ [port])
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
    content_length = Keyword.fetch!(opts, :content_length)

    presign_opts = [
      expires_in: expires_in,
      virtual_host: false,
      headers: [{"content-type", content_type}, {"content-length", Integer.to_string(content_length)}]
    ]

    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :put, bucket, key, presign_opts) do
      {:ok, url} ->
        {:ok, url, %{headers: %{"content-type" => content_type}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def presigned_download_url(key, content_type, opts) do
    expires_in = Keyword.fetch!(opts, :expires_in)
    filename = Keyword.fetch!(opts, :filename)

    presign_opts = [
      expires_in: expires_in,
      virtual_host: false,
      query_params: [
        {"response-cache-control", "private, no-store, no-transform"},
        {"response-content-disposition", ~s(attachment; filename="#{filename}")},
        {"response-content-type", content_type}
      ]
    ]

    :s3
    |> ExAws.Config.new([])
    |> ExAws.S3.presigned_url(:get, bucket(), key, presign_opts)
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
          throw({:object_stream_error, reason})

        _unexpected, _state ->
          throw({:object_stream_error, :unexpected_blob_stream_chunk})
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

  defp normalize_list_page(body, prefix, mode) do
    contents = Map.get(body, :contents, Map.get(body, "Contents", [])) || []
    is_truncated = Map.get(body, :is_truncated, Map.get(body, "IsTruncated"))
    continuation_token = Map.get(body, :next_continuation_token, Map.get(body, "NextContinuationToken"))

    with true <- is_list(contents),
         {:ok, objects} <- normalize_list_objects(contents, prefix, mode),
         {:ok, truncated?} <- normalize_is_truncated(is_truncated),
         {:ok, cursor} <- normalize_list_cursor(continuation_token, truncated?) do
      {:ok, %{objects: objects, cursor: cursor}}
    else
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp normalize_list_objects(contents, prefix, mode) do
    contents
    |> Enum.reduce_while({:ok, []}, fn object, {:ok, objects} ->
      case normalize_list_object(object, prefix, mode) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | objects]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, objects} -> {:ok, Enum.reverse(objects)}
      error -> error
    end
  end

  defp normalize_list_object(object, prefix, :identity) when is_map(object) do
    with {:ok, key} <- decoded_list_key(object),
         true <- Storage.canonical_key?(key) and String.starts_with?(key, prefix),
         {:ok, size} <- normalize_list_size(Map.get(object, :size, Map.get(object, "Size"))),
         {:ok, identity} <- normalize_object_identity(object) do
      {:ok, %{key: key, size: size, identity: identity}}
    else
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp normalize_list_object(object, prefix, :metadata) when is_map(object) do
    with {:ok, key} <- decoded_list_key(object),
         true <- String.starts_with?(key, prefix),
         {:ok, size} <- normalize_list_size(Map.get(object, :size, Map.get(object, "Size"))) do
      {:ok, %{key: key, size: size}}
    else
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp normalize_list_object(_object, _prefix, _mode), do: {:error, :invalid_list_response}

  defp decoded_list_key(object) do
    with key when is_binary(key) <- Map.get(object, :key, Map.get(object, "Key")),
         true <- valid_url_encoding?(key),
         decoded = URI.decode(key),
         true <- String.valid?(decoded) do
      {:ok, decoded}
    else
      _invalid -> {:error, :invalid_list_response}
    end
  end

  defp valid_url_encoding?(<<>>), do: true

  defp valid_url_encoding?(<<?%, high, low, rest::binary>>) do
    hex_digit?(high) and hex_digit?(low) and valid_url_encoding?(rest)
  end

  defp valid_url_encoding?(<<?%, _rest::binary>>), do: false
  defp valid_url_encoding?(<<_byte, rest::binary>>), do: valid_url_encoding?(rest)

  defp hex_digit?(digit), do: digit in ?0..?9 or digit in ?A..?F or digit in ?a..?f

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
