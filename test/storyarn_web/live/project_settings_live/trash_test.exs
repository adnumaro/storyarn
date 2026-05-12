defmodule StoryarnWeb.ProjectSettingsLive.TrashTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Screenplays
  alias Storyarn.Sheets

  defp get_trash_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/Trash")
  end

  defp get_settings_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  describe "Trash page" do
    setup :register_and_log_in_user

    test "renders Trash Vue component for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      settings = get_settings_layout_vue(view)

      assert settings.props["current-path"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"

      assert settings.props["project"]["slug"] == project.slug

      vue = get_trash_vue(view)
      assert vue.component == "live/project/settings/Trash"
      assert vue.props["can-manage"] == true
      assert vue.props["pagination"]["page"] == 1
    end

    test "renders for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert vue.component == "live/project/settings/Trash"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "passes empty list when trash is empty", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert vue.props["trashed-items"] == []
    end

    test "passes all project trash item types to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Deleted Sheet"})
      flow = flow_fixture(project, %{name: "Deleted Flow"})
      scene = scene_fixture(project, %{name: "Deleted Scene"})
      screenplay = screenplay_fixture(project, %{name: "Deleted Screenplay"})

      {:ok, _} = Sheets.delete_sheet(sheet)
      {:ok, _} = Flows.delete_flow(flow)
      {:ok, _} = Scenes.delete_scene(scene)
      {:ok, _} = Screenplays.delete_screenplay(screenplay)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      items = vue.props["trashed-items"]

      assert Enum.any?(items, &match?(%{"type" => "sheet", "name" => "Deleted Sheet"}, &1))
      assert Enum.any?(items, &match?(%{"type" => "flow", "name" => "Deleted Flow"}, &1))
      assert Enum.any?(items, &match?(%{"type" => "scene", "name" => "Deleted Scene"}, &1))
      assert Enum.any?(items, &match?(%{"type" => "screenplay", "name" => "Deleted Screenplay"}, &1))
      assert vue.props["pagination"]["totalCount"] == 4
      assert vue.props["type-counts"] == %{"flow" => 1, "scene" => 1, "screenplay" => 1, "sheet" => 1}
    end

    test "paginates project trash items", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      for index <- 1..26 do
        sheet = sheet_fixture(project, %{name: "Deleted Sheet #{index}"})
        {:ok, _} = Sheets.delete_sheet(sheet)
      end

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      vue = get_trash_vue(view)
      assert length(vue.props["trashed-items"]) == 25
      assert vue.props["pagination"]["totalCount"] == 26
      assert vue.props["pagination"]["totalPages"] == 2

      render_hook(view, "change_trash_page", %{"page" => 2})

      vue = get_trash_vue(view)
      assert vue.props["pagination"]["page"] == 2
      assert length(vue.props["trashed-items"]) == 1
    end

    test "filters project trash items in the backend", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Deleted Sheet"})
      flow = flow_fixture(project, %{name: "Deleted Flow"})

      {:ok, _} = Sheets.delete_sheet(sheet)
      {:ok, _} = Flows.delete_flow(flow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "set_trash_filter", %{"type" => "flow"})

      vue = get_trash_vue(view)
      assert [%{"type" => "flow", "name" => "Deleted Flow"}] = vue.props["trashed-items"]
      assert vue.props["pagination"]["totalCount"] == 1

      render_hook(view, "search_trash", %{"query" => "Sheet"})

      vue = get_trash_vue(view)
      assert vue.props["trashed-items"] == []
      assert vue.props["pagination"]["totalCount"] == 0
    end

    test "restores trashed item by type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Restorable Flow"})
      {:ok, _} = Flows.delete_flow(flow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "restore_item", %{"type" => "flow", "id" => flow.id})

      assert Flows.get_flow(project.id, flow.id)
      refute Enum.any?(get_trash_vue(view).props["trashed-items"], &(&1["id"] == flow.id and &1["type"] == "flow"))
    end

    test "permanently deletes trashed item by type", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Disposable Scene"})
      {:ok, _} = Scenes.delete_scene(scene)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/trash"
        )

      render_hook(view, "delete_item", %{"type" => "scene", "id" => scene.id})

      assert Scenes.get_scene_including_deleted(project.id, scene.id) == nil
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/settings/trash")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
