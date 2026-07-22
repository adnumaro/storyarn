defmodule StoryarnWeb.PrivateDownload do
  @moduledoc """
  Streams authorized private objects through Storyarn without exposing storage URLs.

  The calling controller must authenticate and authorize the resource before
  invoking this module. Browser range requests are supported with bounded
  server-side reads so large media and archives stay out of BEAM memory.
  """

  import Plug.Conn

  alias Storyarn.Assets.Storage
  alias StoryarnWeb.PrivateDownload.Range, as: DownloadRange

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
    DownloadRange.select(
      get_req_header(conn, "range"),
      get_req_header(conn, "if-range"),
      size,
      etag
    )
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
            {:halt, halt(conn)}
        end

      {:error, reason}, conn ->
        Logger.error("Private storage stream failed for #{safe_key_label(key)}: #{inspect(reason)}")
        {:halt, halt(conn)}
    end)
  end

  defp safe_key_label(key), do: key |> Path.basename() |> String.slice(0, 120)
end
