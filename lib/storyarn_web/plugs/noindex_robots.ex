defmodule StoryarnWeb.Plugs.NoindexRobots do
  @moduledoc """
  Serves environment-specific crawler instructions before Plug.Static.

  The default Phoenix convention is a static `priv/static/robots.txt`. Staging
  needs runtime behavior instead, because the same release code can be used in
  public environments where robots should not be blocked.
  """

  import Plug.Conn

  @robots_disallow_all """
  User-agent: *
  Disallow: /
  """

  def init(opts), do: opts

  def call(conn, _opts), do: maybe_serve_noindex_robots(conn)

  defp maybe_serve_noindex_robots(%{method: method, request_path: "/robots.txt"} = conn) when method in ["GET", "HEAD"] do
    if noindex?() do
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, robots_body(method))
      |> halt()
    else
      conn
    end
  end

  defp maybe_serve_noindex_robots(conn), do: conn

  defp noindex?, do: Application.get_env(:storyarn, :noindex, false)

  defp robots_body("HEAD"), do: ""
  defp robots_body(_method), do: @robots_disallow_all
end
