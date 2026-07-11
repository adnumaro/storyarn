defmodule StoryarnWeb.PrivateDownload do
  @moduledoc """
  Streams authorized private objects through Storyarn without exposing storage URLs.

  The calling controller must authenticate and authorize the resource before
  invoking this module. Browser range requests are supported with bounded
  server-side reads so large media and archives stay out of BEAM memory.
  """

  import Plug.Conn

  alias Storyarn.Assets.Storage

  require Logger

  @spec send(Plug.Conn.t(), Storage.key(), keyword()) ::
          {:ok, Plug.Conn.t()} | {:error, term()}
  def send(conn, key, opts) do
    with {:ok, stat} <- Storage.stat(key) do
      selection = select_bytes(conn, stat.size, stat.etag)
      send_selected(conn, key, selection, stat, opts)
    end
  end

  defp send_selected(conn, _key, %{status: :range_not_satisfiable} = selection, _stat, _opts) do
    {:ok,
     conn
     |> put_common_headers(selection)
     |> put_resp_header("content-range", "bytes */#{selection.size}")
     |> send_resp(:requested_range_not_satisfiable, "")}
  end

  defp send_selected(conn, key, selection, stat, opts) do
    with {:ok, stream} <-
           Storage.stream(key, selection.offset, selection.length, etag: stat.etag) do
      {:ok, send_selection(conn, key, stream, selection, stat, opts)}
    end
  end

  defp select_bytes(conn, size, etag) do
    range_headers = get_req_header(conn, "range")

    case get_req_header(conn, "if-range") do
      [] -> parse_range(range_headers, size, etag)
      [if_range] when is_binary(etag) and if_range == etag -> parse_range(range_headers, size, etag)
      _ -> full_selection(size, etag)
    end
  end

  defp parse_range([], size, etag), do: full_selection(size, etag)

  defp parse_range(["bytes=" <> range], 0, etag) do
    if valid_single_range_syntax?(range) do
      unsatisfied_selection(0, etag)
    else
      full_selection(0, etag)
    end
  end

  defp parse_range(["bytes=" <> range], size, etag) do
    if String.contains?(range, ",") do
      full_selection(size, etag)
    else
      parse_single_range(range, size, etag)
    end
  end

  defp parse_range(_range_headers, size, etag), do: full_selection(size, etag)

  defp parse_single_range("-" <> suffix, size, etag) do
    case parse_non_negative_integer(suffix) do
      {:ok, 0} -> unsatisfied_selection(size, etag)
      {:ok, suffix_length} -> partial_selection(max(size - suffix_length, 0), size - 1, size, etag)
      :error -> full_selection(size, etag)
    end
  end

  defp parse_single_range(range, size, etag) do
    case String.split(range, "-", parts: 2) do
      [first, ""] -> parse_open_range(first, size, etag)
      [first, last] -> parse_closed_range(first, last, size, etag)
      _ -> full_selection(size, etag)
    end
  end

  defp parse_open_range(first, size, etag) do
    case parse_non_negative_integer(first) do
      {:ok, first_byte} when first_byte < size ->
        partial_selection(first_byte, size - 1, size, etag)

      {:ok, _first_byte} ->
        unsatisfied_selection(size, etag)

      :error ->
        full_selection(size, etag)
    end
  end

  defp parse_closed_range(first, last, size, etag) do
    with {:ok, first_byte} <- parse_non_negative_integer(first),
         {:ok, last_byte} <- parse_non_negative_integer(last) do
      cond do
        first_byte >= size -> unsatisfied_selection(size, etag)
        last_byte < first_byte -> unsatisfied_selection(size, etag)
        true -> partial_selection(first_byte, min(last_byte, size - 1), size, etag)
      end
    else
      :error -> full_selection(size, etag)
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> :error
    end
  end

  defp valid_single_range_syntax?(range) do
    if String.contains?(range, ",") do
      false
    else
      case String.split(range, "-", parts: 2) do
        ["", suffix] ->
          parse_non_negative_integer(suffix) != :error

        [first, ""] ->
          parse_non_negative_integer(first) != :error

        [first, last] ->
          parse_non_negative_integer(first) != :error and
            parse_non_negative_integer(last) != :error

        _ ->
          false
      end
    end
  end

  defp full_selection(size, etag) do
    %{
      status: :ok,
      offset: 0,
      length: size,
      last_byte: max(size - 1, 0),
      size: size,
      etag: etag
    }
  end

  defp partial_selection(first_byte, last_byte, size, etag) do
    %{
      status: :partial_content,
      offset: first_byte,
      length: last_byte - first_byte + 1,
      last_byte: last_byte,
      size: size,
      etag: etag
    }
  end

  defp unsatisfied_selection(size, etag) do
    %{
      status: :range_not_satisfiable,
      offset: 0,
      length: 0,
      last_byte: 0,
      size: size,
      etag: etag
    }
  end

  defp send_selection(conn, key, stream, selection, stat, opts) do
    content_type =
      Keyword.get(opts, :content_type) || stat.content_type || "application/octet-stream"

    conn =
      conn
      |> put_common_headers(selection)
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("content-length", Integer.to_string(selection.length))
      |> maybe_put_content_range(selection)
      |> maybe_put_content_disposition(Keyword.get(opts, :filename))
      |> send_chunked(selection.status)

    send_stream(conn, key, stream)
  end

  defp put_common_headers(conn, selection) do
    conn
    |> put_resp_header("accept-ranges", "bytes")
    |> put_resp_header("cache-control", "private, no-store, no-transform")
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
    |> put_resp_header("cross-origin-resource-policy", "same-origin")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> maybe_put_etag(selection.etag)
  end

  defp maybe_put_content_range(conn, %{status: :partial_content} = selection) do
    put_resp_header(
      conn,
      "content-range",
      "bytes #{selection.offset}-#{selection.last_byte}/#{selection.size}"
    )
  end

  defp maybe_put_content_range(conn, _selection), do: conn

  defp maybe_put_content_disposition(conn, nil), do: conn

  defp maybe_put_content_disposition(conn, filename) do
    safe_filename = String.replace(filename, ["\r", "\n", "\"", "\\"], "_")
    put_resp_header(conn, "content-disposition", ~s(attachment; filename="#{safe_filename}"))
  end

  defp maybe_put_etag(conn, nil), do: conn
  defp maybe_put_etag(conn, etag), do: put_resp_header(conn, "etag", etag)

  defp send_stream(conn, key, stream) do
    Enum.reduce_while(stream, conn, fn
      {:ok, data}, conn ->
        case chunk(conn, data) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, :closed} ->
            {:halt, conn}

          {:error, reason} ->
            Logger.warning("Private download client stream failed: #{inspect(reason)}")
            raise "private download transport failed"
        end

      {:error, reason}, _conn ->
        Logger.error("Private storage stream failed for #{safe_key_label(key)}: #{inspect(reason)}")
        raise "private storage stream failed"
    end)
  end

  defp safe_key_label(key), do: key |> Path.basename() |> String.slice(0, 120)
end
