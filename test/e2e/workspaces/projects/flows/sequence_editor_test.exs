defmodule StoryarnWeb.E2E.FlowSequenceEditorTest do
  @moduledoc """
  Real-browser coverage for the static sequence workspace.

  The fixture records point at a local asset URL; this test does not upload
  files or depend on an external media service.

  Run with:
      mix test test/e2e/workspaces/projects/flows/sequence_editor_test.exs --include e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Flows
  alias Storyarn.Repo

  @moduletag :e2e

  test "a dialogue shows its inherited static composition and keeps the stage above debug", %{
    conn: conn
  } do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Sequence workspace"})

    backdrop =
      image_asset_fixture(project, user, %{
        filename: "rainy-courtyard.png",
        url: "/uploads/rainy-courtyard.png"
      })

    {:ok, source} =
      Flows.create_sequence(flow.id, %{
        "name" => "Rainy courtyard",
        "position_x" => 120.0,
        "position_y" => 120.0
      })

    {:ok, _layer} =
      Flows.create_sequence_visual_layer(source.id, %{
        asset_id: backdrop.id,
        kind: "backdrop",
        label: "Courtyard backdrop"
      })

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        position_x: 520.0,
        position_y: 120.0,
        composition_source_id: source.id,
        data: %{
          "text" => "<p>We take the eastern gate.</p>",
          "stage_directions" => "under the rain",
          "responses" => []
        }
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

    conn
    |> authenticate(user)
    |> visit(path)
    |> assert_has("#flow-sequence-stage[data-status='empty']", timeout: 20_000)
    |> assert_has("[data-flow-comment-node='#{dialogue.id}'] [data-testid='node']",
      timeout: 20_000
    )
    |> click("[data-flow-comment-node='#{dialogue.id}'] [data-testid='node']")
    |> assert_has("#flow-sequence-stage[data-status='ready']", timeout: 20_000)
    |> assert_has("[data-sequence-intervention]", text: "We take the eastern gate.")
    |> assert_has(
      ".sequence-visual-layer[data-origin-node-id='#{source.id}'][data-inherited='true'] img[alt='Courtyard backdrop']"
    )
    |> click("[data-open-sequence-inspector]")
    |> assert_has(".right-sidebar [data-composition-source]", timeout: 20_000)
    |> assert_has(".right-sidebar [data-composition-source-trigger]", text: "Rainy courtyard")
    |> click(".right-sidebar button[aria-label='Close']")
    |> click("[data-testid='flow-dock'] > .dock-item:last-child button")
    |> assert_has("[data-flow-workspace='debug']", text: "Paused", timeout: 20_000)
    |> refute_has("[data-flow-workspace='canvas']")
    |> assert_has("#flow-sequence-stage")
    |> click("[data-flow-workspace='debug'] button[title='Stop']")
    |> assert_has("[data-flow-workspace='canvas']", timeout: 20_000)
    |> refute_has("[data-flow-workspace='debug']")
    |> assert_has("#flow-sequence-stage[data-status='ready']")
  end
end
