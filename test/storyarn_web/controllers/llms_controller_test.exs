defmodule StoryarnWeb.LlmsControllerTest do
  use StoryarnWeb.ConnCase, async: true

  test "GET /llms.txt renders an LLM-friendly public index", %{conn: conn} do
    conn = get(conn, ~p"/llms.txt")
    body = response(conn, 200)

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/markdown"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]

    assert body =~ "# Storyarn"
    assert body =~ "> Storyarn is a narrative design platform"
    assert body =~ "## Product"
    assert body =~ "## Welcome"
    assert body =~ "## Optional"

    assert body =~ ~r"\[Storyarn\]\(http://localhost:\d+/\)"
    assert body =~ ~r"\[Documentation\]\(http://localhost:\d+/docs\)"
    assert body =~ ~r"\[What is Storyarn\?\]\(http://localhost:\d+/docs/welcome/what-is-storyarn\)"
    assert body =~ ~r"\[Flows Overview\]\(http://localhost:\d+/docs/narrative-design/flows-overview\)"
    assert body =~ ~r"\[Privacy Policy\]\(http://localhost:\d+/privacy\)"

    refute body =~ "<!DOCTYPE html>"
    refute body =~ "/users/log-in"
    refute body =~ "/projects/invitations"
    refute body =~ "/workspaces/"
  end
end
