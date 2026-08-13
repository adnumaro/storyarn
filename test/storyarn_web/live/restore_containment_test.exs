defmodule StoryarnWeb.RestoreContainmentTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy

  setup :register_and_log_in_user

  setup do
    original_config =
      Application.get_env(:storyarn, RestorePolicy)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: false,
      flow_version_restore: false,
      scene_version_restore: false
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

    params = %{
      "version_number" => to_string(version.version_number),
      "request_id" => "contained-request"
    }

    render_click(view, "preview_restore", params)
    render_click(view, "review_restore", params)
    render_click(view, "confirm_restore", params)

    assert Sheets.get_sheet(project.id, sheet.id).name == "Changed"
    assert Enum.map(Sheets.list_blocks(sheet.id), & &1.id) == [block.id]
    assert Versioning.count_versions("sheet", sheet.id) == 1
    refute_push_event(view, "show_unsaved_modal", %{})
    refute_push_event(view, "show_restore_modal", %{})
    refute_push_event(view, "version_restored", %{})
  end
end
