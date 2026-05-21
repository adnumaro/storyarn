defmodule StoryarnWeb.Plugs.NoindexRobotsTest do
  use StoryarnWeb.ConnCase, async: false

  alias StoryarnWeb.Plugs.NoindexRobots

  setup do
    original_noindex = Application.fetch_env(:storyarn, :noindex)

    on_exit(fn -> restore_env(:noindex, original_noindex) end)
  end

  test "serves restrictive robots.txt when NOINDEX is enabled" do
    Application.put_env(:storyarn, :noindex, true)

    conn =
      :get
      |> build_conn("/robots.txt")
      |> NoindexRobots.call([])

    assert conn.halted
    assert response(conn, 200) == "User-agent: *\nDisallow: /\n"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "leaves robots.txt to Plug.Static when NOINDEX is disabled" do
    Application.put_env(:storyarn, :noindex, false)

    conn =
      :get
      |> build_conn("/robots.txt")
      |> NoindexRobots.call([])

    refute conn.halted
  end

  test "endpoint serves restrictive robots.txt before Plug.Static", %{conn: conn} do
    Application.put_env(:storyarn, :noindex, true)

    conn = get(conn, "/robots.txt")

    assert response(conn, 200) == "User-agent: *\nDisallow: /\n"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "endpoint serves the default static robots.txt when NOINDEX is disabled", %{conn: conn} do
    Application.put_env(:storyarn, :noindex, false)

    conn = get(conn, "/robots.txt")

    assert response(conn, 200) =~ "robotstxt.org"
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:storyarn, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:storyarn, key)
end
