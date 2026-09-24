defmodule StoryarnWeb.PublicLocaleRedirectControllerTest do
  use StoryarnWeb.ConnCase, async: true

  for {source, target} <- [
        {"/en", "/"},
        {"/en/contact", "/contact"},
        {"/en/privacy", "/privacy"},
        {"/en/terms", "/terms"},
        {"/en/docs", "/docs"},
        {"/en/docs/welcome/start-here", "/docs/welcome/start-here"},
        {"/en/blog", "/blog"},
        {"/en/blog/introducing-storyarn", "/blog/introducing-storyarn"},
        {"/en/users/log-in", "/users/log-in"},
        {"/en/users/register", "/users/register"},
        {"/en/users/register/token", "/users/register/token"},
        {"/en/users/reset-password", "/users/reset-password"},
        {"/en/users/reset-password/token", "/users/reset-password/token"},
        {"/en/projects/invitations/token", "/projects/invitations/token"},
        {"/en/workspaces/invitations/token", "/workspaces/invitations/token"}
      ] do
    test "permanently redirects #{source} to #{target}", %{conn: conn} do
      conn = get(conn, unquote(source))

      assert redirected_to(conn, :moved_permanently) == unquote(target)
    end
  end

  test "preserves query parameters in the canonical redirect", %{conn: conn} do
    conn = get(conn, "/en/docs/welcome/start-here?utm_source=legacy")

    assert redirected_to(conn, :moved_permanently) ==
             "/docs/welcome/start-here?utm_source=legacy"
  end
end
