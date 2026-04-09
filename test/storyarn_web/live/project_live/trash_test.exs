defmodule StoryarnWeb.ProjectLive.TrashTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  defp get_trash_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/project-settings/Trash")
  end

  describe "Trash page" do
    setup :register_and_log_in_user

    test "renders Trash Vue component for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/trash"
        )

      vue = get_trash_vue(view)
      assert vue.component == "modules/project-settings/Trash"
      assert vue.props["can-manage"] == true
    end

    test "renders for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/trash"
        )

      vue = get_trash_vue(view)
      assert vue.component == "modules/project-settings/Trash"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/trash"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "passes empty list when trash is empty", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/trash"
        )

      vue = get_trash_vue(view)
      assert vue.props["trashed-sheets"] == []
    end

    test "passes trashed sheets to Vue", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Deleted Sheet"})

      # Soft-delete the sheet
      {:ok, _} = Sheets.delete_sheet(sheet)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/trash"
        )

      vue = get_trash_vue(view)
      assert Enum.any?(vue.props["trashed-sheets"], fn s -> s["name"] == "Deleted Sheet" end)
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/trash")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
