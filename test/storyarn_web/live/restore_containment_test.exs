defmodule StoryarnWeb.RestoreContainmentTest do
  use StoryarnWeb.ConnCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Workers.RecoverProjectWorker
  alias Storyarn.Workers.RestoreProjectWorker

  setup :register_and_log_in_user

  setup do
    original_config =
      Application.get_env(:storyarn, RestorePolicy)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: false,
      flow_version_restore: false,
      scene_version_restore: false,
      project_snapshot_restore: false,
      deleted_project_recovery: false
    )

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_config)
      end
    end)

    :ok
  end

  test "Sheet, Flow, and Scene expose an explicit disabled restore capability", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    sheet = sheet_fixture(project)

    sheet_url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    {:ok, sheet_view, _html} = live(conn, sheet_url)
    await_async(sheet_view)
    render_click(sheet_view, "switch_tab", %{"tab" => "history"})

    sheet_vue =
      LiveVue.Test.get_vue(
        sheet_view,
        name: "live/sheet/show/SheetSurface"
      )

    assert sheet_vue.props["panels"]["history"]["restoreEnabled"] == false

    flow = flow_fixture(project)

    flow_url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

    {:ok, flow_view, _html} = live(conn, flow_url)
    await_async(flow_view)

    flow_vue =
      LiveVue.Test.get_vue(
        flow_view,
        name: "live/flow/show/FlowPanels"
      )

    assert flow_vue.props["panels"]["versions"]["restoreEnabled"] == false

    scene = scene_fixture(project)

    scene_url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"

    {:ok, scene_view, _html} = live(conn, scene_url)
    await_async(scene_view)

    scene_vue =
      LiveVue.Test.get_vue(
        scene_view,
        name: "live/scene/show/ScenePanels"
      )

    assert scene_vue.props["panels"]["versions"]["restoreEnabled"] == false
  end

  test "forged Sheet restore events do not mutate data or create a backup", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Original"})
    block = block_fixture(sheet)

    {:ok, version} =
      Versioning.create_version("sheet", sheet, project.id, user.id, title: "Restore target")

    {:ok, _changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed"})

    url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    {:ok, view, _html} = live(conn, url)
    await_async(view)

    params = %{"version_number" => to_string(version.version_number)}

    render_click(view, "preview_restore", params)
    render_click(view, "save_and_restore", params)
    render_click(view, "discard_and_restore", params)

    render_click(
      view,
      "confirm_restore",
      Map.put(params, "skip_pre_snapshot", true)
    )

    assert Sheets.get_sheet(project.id, sheet.id).name == "Changed"
    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == [block.id]
    assert Versioning.count_versions("sheet", sheet.id) == 1
    refute_push_event(view, "show_unsaved_modal", %{})
    refute_push_event(view, "show_restore_modal", %{})
    refute_push_event(view, "version_restored", %{})
  end

  test "project snapshot restore is hidden and a forged event creates no lock or job", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project.id, user.id, title: "Safe copy")

    url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"

    {:ok, view, _html} = live(conn, url)

    vue =
      LiveVue.Test.get_vue(
        view,
        name: "live/project/settings/ProjectSettingsSnapshots"
      )

    assert vue.props["restore-enabled"] == false

    render_click(view, "restore_snapshot", %{"id" => snapshot.id})

    refute Projects.restoration_in_progress?(project.id)
    refute_enqueued(worker: RestoreProjectWorker)
    assert Versioning.count_project_snapshots(project.id) == 1
  end

  test "deleted-project recovery is hidden and forged events create no job", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project.id, user.id, title: "Recovery point")

    {:ok, _deleted_project} = Projects.delete_project(project, user.id)

    url =
      ~p"/users/settings/workspaces/#{project.workspace.slug}/deleted-projects"

    {:ok, view, _html} = live(conn, url)

    vue =
      LiveVue.Test.get_vue(
        view,
        name: "live/workspace/settings/WorkspaceSettingsDeletedProjects"
      )

    assert vue.props["recovery-enabled"] == false

    render_click(view, "toggle_project", %{"id" => project.id})

    render_click(view, "recover_project", %{
      "project_id" => project.id,
      "snapshot_id" => snapshot.id
    })

    refute_enqueued(worker: RecoverProjectWorker)
    assert Repo.get(Projects.Project, project.id)
  end

  test "the deleted-project screen cannot inspect another workspace's snapshots", %{
    conn: conn,
    user: user
  } do
    destination_project =
      user
      |> project_fixture()
      |> Repo.preload(:workspace)

    source_user = Storyarn.AccountsFixtures.user_fixture()
    source_project = project_fixture(source_user)

    {:ok, _snapshot} =
      Versioning.create_project_snapshot(source_project.id, source_user.id, title: "Private snapshot")

    {:ok, _deleted_project} =
      Projects.delete_project(source_project, source_user.id)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: false,
      flow_version_restore: false,
      scene_version_restore: false,
      project_snapshot_restore: false,
      deleted_project_recovery: true
    )

    url =
      ~p"/users/settings/workspaces/#{destination_project.workspace.slug}/deleted-projects"

    {:ok, view, _html} = live(conn, url)
    render_click(view, "toggle_project", %{"id" => source_project.id})

    vue =
      LiveVue.Test.get_vue(
        view,
        name: "live/workspace/settings/WorkspaceSettingsDeletedProjects"
      )

    assert vue.props["expanded-project-id"] == nil
    assert vue.props["snapshots"] == []
  end
end
