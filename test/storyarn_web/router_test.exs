defmodule StoryarnWeb.RouterTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  # ── Public routes ──────────────────────────────────────────────

  describe "public routes" do
    test "home page is accessible", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end

    test "login page is accessible", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      assert html_response(conn, 200)
    end

    test "registration page is accessible", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      assert html_response(conn, 200)
    end
  end

  # ── Auth gating ────────────────────────────────────────────────

  describe "authentication gating" do
    test "redirects to login for unauthenticated workspace access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated settings access", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated connections access", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/connections")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated project access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated sheet access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/sheets")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated flow access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/flows")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated scene access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/scenes")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated screenplay access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/screenplays")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated localization access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/localization")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated assets access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/assets")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated trash access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/trash")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "redirects to login for unauthenticated export-import access", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/test-ws/projects/test-proj/export-import")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  # ── Authenticated access ───────────────────────────────────────

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "workspaces page redirects to default workspace", %{conn: conn} do
      conn = get(conn, ~p"/workspaces")
      # Redirects to user's default workspace
      assert redirected_to(conn) =~ "/workspaces/"
    end

    test "profile settings is accessible", %{conn: conn} do
      conn = get(conn, ~p"/users/settings")
      assert html_response(conn, 200)
    end

    test "workspace creation is accessible", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/new")
      assert html_response(conn, 200)
    end
  end

  # ── OAuth routes ───────────────────────────────────────────────

  describe "OAuth routes" do
    test "OAuth routes are defined in the router" do
      # Verify path helpers resolve — proves routes exist in the router
      assert ~p"/auth/github" == "/auth/github"
      assert ~p"/auth/google" == "/auth/google"
      assert ~p"/auth/discord" == "/auth/discord"
      assert ~p"/auth/github/callback" == "/auth/github/callback"
      assert ~p"/auth/google/callback" == "/auth/google/callback"
    end

    test "OAuth link route requires auth", %{conn: conn} do
      conn = get(conn, ~p"/auth/github/link")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  # ── Session routes ─────────────────────────────────────────────

  describe "session routes" do
    test "POST login route exists", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => "test@example.com", "password" => "wrong"}
        })

      # Should redirect back to login with error
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "DELETE logout route exists", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
    end
  end

  # ── CSP headers ────────────────────────────────────────────────

  describe "CSP headers" do
    test "sets content-security-policy header", %{conn: conn} do
      conn = get(conn, ~p"/")
      csp = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert length(csp) > 0
      [policy] = csp
      assert policy =~ "default-src 'self'"
      assert policy =~ "script-src 'self'"
      assert policy =~ "frame-ancestors 'self'"
    end
  end

  # ── Export controller routes ───────────────────────────────────

  describe "export controller routes" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "screenplay fountain export requires auth", %{conn: conn} do
      # Non-authed request
      conn = conn |> delete_req_header("cookie") |> Phoenix.ConnTest.recycle()
      conn = get(conn, "/workspaces/ws/projects/proj/screenplays/1/export/fountain")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "project export route requires auth", %{conn: conn} do
      conn = conn |> delete_req_header("cookie") |> Phoenix.ConnTest.recycle()
      conn = get(conn, "/workspaces/ws/projects/proj/export/storyarn_json")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  # ── Invitation routes ──────────────────────────────────────────

  describe "invitation routes" do
    test "project invitation is accessible without auth", %{conn: conn} do
      conn = get(conn, ~p"/projects/invitations/some-token")
      # Should render (even if token is invalid, it should reach the LiveView)
      assert html_response(conn, 200)
    end

    test "workspace invitation is accessible without auth", %{conn: conn} do
      conn = get(conn, ~p"/workspaces/invitations/some-token")
      assert html_response(conn, 200)
    end
  end
end
