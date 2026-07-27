defmodule StoryarnWeb.Live.Shared.DashboardRowActionsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias StoryarnWeb.SceneSidebarLive
  alias StoryarnWeb.SheetsSidebarLive

  setup :register_and_log_in_user

  test "the sheets dashboard deletes its row through its own LiveView and notifies the shell", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Doomed sheet"})
    :ok = Phoenix.PubSub.subscribe(Storyarn.PubSub, SheetsSidebarLive.shell_topic(project.id))

    {:ok, view, _html} = live(conn, sheets_path(project))
    await_async(view)

    render_click(view, "set_pending_delete_sheet", %{"id" => sheet.id})
    render_click(view, "confirm_delete_sheet")

    refute Sheets.get_sheet(project.id, sheet.id)
    assert_receive {:entities_deleted, :sheet, [sheet_id]}
    assert sheet_id == sheet.id
    assert_receive {:tree_changed, :sheets}
    assert Process.alive?(view.pid)
  end

  test "the sheets dashboard rejects direct deletion events from viewers", %{
    conn: conn,
    user: viewer
  } do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    _membership = membership_fixture(project, viewer, "viewer")
    sheet = sheet_fixture(project, %{name: "Protected sheet"})

    {:ok, view, _html} = live(conn, sheets_path(project))
    await_async(view)

    render_click(view, "set_pending_delete_sheet", %{"id" => sheet.id})
    render_click(view, "confirm_delete_sheet")

    assert Sheets.get_sheet(project.id, sheet.id)
    assert Process.alive?(view.pid)
  end

  test "the scenes dashboard deletes its row through its own LiveView and notifies the shell", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Doomed scene"})
    :ok = Phoenix.PubSub.subscribe(Storyarn.PubSub, SceneSidebarLive.shell_topic(project.id))

    {:ok, view, _html} = live(conn, scenes_path(project))
    await_async(view)

    render_click(view, "set_pending_delete_scene", %{"id" => scene.id})
    render_click(view, "confirm_delete_scene")

    refute Scenes.get_scene(project.id, scene.id)
    assert_receive {:entities_deleted, :scene, [scene_id]}
    assert scene_id == scene.id
    assert_receive {:tree_changed, :scenes}
    assert Process.alive?(view.pid)
  end

  test "the scenes dashboard rejects direct deletion events from viewers", %{
    conn: conn,
    user: viewer
  } do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    _membership = membership_fixture(project, viewer, "viewer")
    scene = scene_fixture(project, %{name: "Protected scene"})

    {:ok, view, _html} = live(conn, scenes_path(project))
    await_async(view)

    render_click(view, "set_pending_delete_scene", %{"id" => scene.id})
    render_click(view, "confirm_delete_scene")

    assert Scenes.get_scene(project.id, scene.id)
    assert Process.alive?(view.pid)
  end

  defp sheets_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
  end

  defp scenes_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
  end
end
