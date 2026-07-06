defmodule StoryarnWeb.Plugs.CanonicalHostRedirect do
  @moduledoc """
  Redirects apex production hosts to the canonical public host.

  Storyarn's public URLs are canonicalized under `www.storyarn.com`. This plug
  keeps requests that reach Phoenix with `Host: storyarn.com` from serving the
  same HTML, docs, robots.txt, or static assets under the apex domain.
  """

  @behaviour Plug

  import Plug.Conn

  @default_redirects %{"storyarn.com" => "www.storyarn.com"}

  @impl true
  def init(opts) do
    opts
    |> Keyword.get(:redirects, @default_redirects)
    |> Map.new(fn {source, target} -> {normalize_host(source), normalize_host(target)} end)
  end

  @impl true
  def call(conn, redirects) do
    host = normalize_host(conn.host)

    case Map.fetch(redirects, host) do
      {:ok, target_host} ->
        conn
        |> put_resp_header("location", canonical_url(conn, target_host))
        |> send_resp(308, "")
        |> halt()

      :error ->
        conn
    end
  end

  defp canonical_url(conn, target_host) do
    "https://" <> target_host <> conn.request_path <> query_suffix(conn.query_string)
  end

  defp query_suffix(""), do: ""
  defp query_suffix(query_string), do: "?" <> query_string

  defp normalize_host(host) do
    host
    |> to_string()
    |> String.trim_trailing(".")
    |> String.downcase()
  end
end
