defmodule StoryarnWeb.OnboardingIntegrationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo

  setup %{conn: conn} do
    user =
      user_fixture()
      |> Ecto.Changeset.change(onboarding_started_at: DateTime.utc_now(:second))
      |> Repo.update!()

    %{conn: log_in_user(conn, user), user: user}
  end

  test "workspace dashboard auto-starts and persists its tutorial", %{conn: conn, user: user} do
    workspace = workspace_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

    assert onboarding_config(view, "workspace")["autoShow"]

    render_click(view, "complete_onboarding_tutorial", %{
      "tutorial" => "workspace",
      "source" => "auto"
    })

    refute onboarding_config(view, "workspace")["autoShow"]
  end

  test "sheet editor auto-starts the sheets tutorial", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )

    assert onboarding_config(view, "sheets")["autoShow"]
  end

  test "flow editor auto-starts the flows tutorial", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      )

    assert onboarding_config(view, "flows")["autoShow"]
  end

  test "scene editor auto-starts the scenes tutorial", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
      )

    assert onboarding_config(view, "scenes")["autoShow"]
  end

  test "localization report auto-starts the localization tutorial", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization"
      )

    assert onboarding_config(view, "localization")["autoShow"]
  end

  test "export settings auto-starts the export tutorial", %{conn: conn, user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
      )

    layout = LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
    assert layout.props["onboarding"] == %{"guide" => "export", "autoShow" => true}
  end

  defp onboarding_config(view, guide) do
    layout_name =
      if guide == "workspace",
        do: "live/layouts/workspace/Layout",
        else: "live/layouts/project/Layout"

    layout = LiveVue.Test.get_vue(view, name: layout_name)
    assert layout.props["onboarding"]["guide"] == guide
    layout.props["onboarding"]
  end
end
