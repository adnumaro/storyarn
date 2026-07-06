defmodule StoryarnWeb.Plugs.CanonicalHostRedirectTest do
  use StoryarnWeb.ConnCase, async: true

  alias StoryarnWeb.Plugs.CanonicalHostRedirect

  test "redirects the apex host to the canonical www host" do
    conn =
      :get
      |> build_conn("https://storyarn.com/docs/welcome?utm_source=launch")
      |> CanonicalHostRedirect.call(CanonicalHostRedirect.init([]))

    assert conn.halted
    assert conn.status == 308

    assert get_resp_header(conn, "location") == [
             "https://www.storyarn.com/docs/welcome?utm_source=launch"
           ]
  end

  test "normalizes host case and trailing dot" do
    conn =
      :get
      |> build_conn("https://Storyarn.COM./")
      |> CanonicalHostRedirect.call(CanonicalHostRedirect.init([]))

    assert conn.halted
    assert get_resp_header(conn, "location") == ["https://www.storyarn.com/"]
  end

  test "does not redirect the canonical host" do
    conn =
      :get
      |> build_conn("https://www.storyarn.com/docs")
      |> CanonicalHostRedirect.call(CanonicalHostRedirect.init([]))

    refute conn.halted
  end

  test "does not redirect other subdomains" do
    conn =
      :get
      |> build_conn("https://app.storyarn.com/docs")
      |> CanonicalHostRedirect.call(CanonicalHostRedirect.init([]))

    refute conn.halted
  end

  test "endpoint redirects robots.txt before static or noindex handling" do
    conn =
      :get
      |> build_conn("https://storyarn.com/robots.txt")
      |> StoryarnWeb.Endpoint.call([])

    assert conn.halted
    assert conn.status == 308
    assert get_resp_header(conn, "location") == ["https://www.storyarn.com/robots.txt"]
    assert conn.resp_body == ""
  end
end
