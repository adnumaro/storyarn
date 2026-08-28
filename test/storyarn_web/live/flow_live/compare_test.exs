defmodule StoryarnWeb.FlowLive.CompareTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  setup :register_and_log_in_user

  test "loads Flow identity and version navigation through the Flow boundary", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Chapter One"})
    {:ok, version} = Flows.create_version(flow, user.id, title: "Milestone")

    path =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/compare/#{version.version_number}"

    {:ok, view, _html} = live(conn, path)

    compare = LiveVue.Test.get_vue(view, name: "live/versioning/compare/VersioningCompare")

    assert compare.props["version-label"] == "v1 — Milestone"

    assert compare.props["current-url"] ==
             ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"

    assert compare.props["version-url"] ==
             ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/versions/1/viewer"
  end
end
