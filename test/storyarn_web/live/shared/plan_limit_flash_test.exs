defmodule StoryarnWeb.Live.Shared.PlanLimitFlashTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo

  setup :register_and_log_in_user

  defp flash(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup").props["flash"]
  end

  defp fill_workspace_with_projects!(owner, workspace) do
    scope = user_scope_fixture(owner)

    for i <- 1..3 do
      {:ok, _project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Project #{i}",
          workspace_id: workspace.id,
          project_type: "game",
          project_subtype: "rpg"
        })
    end
  end

  defp create_project(view) do
    render_hook(view, "create_project", %{
      "project" => %{"name" => "One too many", "project_type" => "game", "project_subtype" => "rpg"}
    })
  end

  defp fill_project_with_items!(project) do
    {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Big"})
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      "flow_nodes",
      for i <- 1..697 do
        %{
          flow_id: flow.id,
          type: "dialogue",
          position_x: i * 1.0,
          position_y: 0.0,
          data: %{},
          inserted_at: now,
          updated_at: now
        }
      end
    )
  end

  test "a workspace owner who hits a limit gets a link to Plan & billing", %{conn: conn, user: user} do
    workspace = workspace_fixture(user)
    fill_workspace_with_projects!(user, workspace)

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")
    create_project(view)

    assert flash(view)["limit"] == %{
             "message" => "Project limit reached for your plan",
             "planPath" => "/users/settings/plan"
           }

    assert flash(view)["error"] == nil
  end

  test "admins and members see the notice without the link: the plan is the owner's", %{conn: conn} do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    fill_workspace_with_projects!(owner, workspace)

    for role <- ["admin", "member"] do
      editor = user_fixture()
      workspace_membership_fixture(workspace, editor, role)

      {:ok, view, _html} =
        conn |> recycle() |> log_in_user(editor) |> live(~p"/workspaces/#{workspace.slug}")

      create_project(view)

      assert flash(view)["limit"] == %{
               "message" => "Project limit reached for your plan",
               "planPath" => nil
             },
             role
    end
  end

  test "a limit hit in the sidebar reaches the page's toaster", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    fill_project_with_items!(project)

    {:ok, view, _html} =
      live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

    view
    |> find_live_child("sidebar-sheets-#{project.id}")
    |> render_click("create_sheet", %{})

    assert flash(view)["limit"] == %{
             "message" => "Item limit reached for your plan",
             "planPath" => "/users/settings/plan"
           }
  end

  test "a named version over the limit says so instead of a generic failure", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = project |> sheet_fixture() |> Repo.preload(:blocks, force: true)

    for i <- 1..10 do
      {:ok, _version} = Storyarn.Sheets.create_version(sheet, user.id, title: "v#{i}")
    end

    {:ok, view, _html} =
      live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")

    render_click(view, "create_version", %{"title" => "Eleventh", "description" => ""})

    assert flash(view)["limit"]["message"] == "Named version limit reached for your plan."
    assert flash(view)["error"] == nil
  end
end
