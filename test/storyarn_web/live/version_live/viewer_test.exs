defmodule StoryarnWeb.VersionLive.ViewerTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning

  describe "version viewer" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      sheet = Repo.preload(sheet, :blocks, force: true)

      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "v1")

      %{project: project, sheet: sheet, version: version}
    end

    test "renders sheet version snapshot", %{conn: conn, project: project, sheet: sheet} do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/sheet/#{sheet.id}/1"
        )

      assert html =~ "v1"
      assert html =~ "Test Sheet"
    end

    test "redirects for invalid entity type", %{conn: conn, project: project, sheet: sheet} do
      result =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/invalid/#{sheet.id}/1"
        )

      assert {:error, {:redirect, %{to: "/workspaces"}}} = result
    end

    test "redirects for non-existent version number", %{
      conn: conn,
      project: project,
      sheet: sheet
    } do
      result =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/sheet/#{sheet.id}/999"
        )

      assert {:error, {:redirect, %{to: "/workspaces"}}} = result
    end

    test "redirects for non-existent entity id", %{conn: conn, project: project} do
      result =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/sheet/999999/1"
        )

      assert {:error, {:redirect, %{to: "/workspaces"}}} = result
    end

    test "redirects unauthenticated user" do
      conn = build_conn()
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      result =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/sheet/1/1"
        )

      assert {:error, {:redirect, %{to: path}}} = result
      assert path =~ "/users/log-in"
    end

    test "blocks access for non-member", %{project: project, sheet: sheet} do
      non_member = user_fixture()
      conn = log_in_user(build_conn(), non_member)

      result =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/versions/sheet/#{sheet.id}/1"
        )

      # Non-member can't resolve the project, so gets redirected
      assert {:error, {:redirect, %{to: "/workspaces"}}} = result
    end

    test "validates version belongs to correct project", %{conn: conn, user: user, sheet: sheet} do
      # Create another project that the user owns
      other_project = project_fixture(user) |> Repo.preload(:workspace)

      # Try to access the version via the wrong project
      result =
        live(
          conn,
          ~p"/workspaces/#{other_project.workspace.slug}/projects/#{other_project.slug}/versions/sheet/#{sheet.id}/1"
        )

      assert {:error, {:redirect, %{to: "/workspaces"}}} = result
    end
  end
end
