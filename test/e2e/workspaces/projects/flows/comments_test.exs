defmodule StoryarnWeb.E2E.FlowCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Repo

  @moduletag :e2e

  test "an editor starts a node discussion, resolves it and finds it after reloading", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Reviewable encounter"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 480,
        position_y: 180,
        data: %{"label" => "Guard encounter", "hub_id" => "guard_encounter"}
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "Give the player a reason to trust the guard before this encounter."

    conn
    |> authenticate(user)
    |> visit(path)
    |> assert_has("#flow-node-comments-#{node.id}", timeout: 20_000)
    |> click("#flow-node-comments-#{node.id}")
    |> fill_in("#flow-comment-body", "New thread", with: feedback)
    |> click("#flow-comment-send")
    |> assert_has("#flow-comments-content", text: feedback)
    |> assert_has("#flow-comment-status", text: "Resolve")
    |> click("#flow-comment-status")
    |> assert_has("#flow-comment-status", text: "Reopen")
    |> assert_has("#flow-comments-content", text: "This thread is resolved.")
    |> visit(path)
    |> assert_has("#flow-node-comments-#{node.id}", timeout: 20_000)
    |> click("#flow-comments-toggle")
    |> select("#flow-comments-filter", "Filter threads", option: "Resolved")
    |> assert_has("#flow-comments-content", text: "Give the player a reason to trust the guard")
  end
end
