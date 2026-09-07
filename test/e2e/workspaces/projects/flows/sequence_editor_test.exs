defmodule StoryarnWeb.E2E.FlowSequenceEditorTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Flows
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Repo

  @moduletag :e2e
  @moduletag :sequence_completion

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Sequence workspace"})
    entry = Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))

    first =
      node_fixture(flow, %{
        type: "dialogue",
        position_x: 280,
        position_y: 100,
        data: %{"text" => "We take the eastern gate.", "responses" => []}
      })

    second =
      node_fixture(flow, %{
        type: "dialogue",
        position_x: 700,
        position_y: 100,
        data: %{"text" => "The courtyard is empty.", "responses" => []}
      })

    connection_fixture(flow, entry, first)
    connection_fixture(flow, first, second)
    {:ok, _} = Flows.set_composition_source(second.id, first.id)
    backdrop = image_asset_fixture(project, user, %{filename: "courtyard.png"})
    {:ok, _} = ObjectStorage.upload(backdrop.key, File.read!("test/fixtures/images/quadrant_map.png"), "image/png")
    on_exit(fn -> ObjectStorage.delete(backdrop.key) end)

    {:ok, layer} =
      Flows.create_sequence_visual_layer(first.id, %{
        asset_id: backdrop.id,
        kind: "backdrop",
        label: "Courtyard backdrop",
        width: 1.4,
        height: 1.4,
        x: -0.2,
        y: -0.2
      })

    %{
      user: user,
      project: project,
      flow: flow,
      first: first,
      second: second,
      layer: layer,
      path: "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    }
  end

  test "opens only on Play, supports comments and inline playback, and closes on Stop", context do
    context.conn
    |> authenticate(context.user)
    |> visit(context.path)
    |> assert_has("[data-toggle-visual-editor]", timeout: 20_000)
    |> refute_has("[data-sequence-workspace]")
    |> click("[data-flow-comment-node='#{context.first.id}'] [data-testid='node']")
    |> click("[data-toggle-visual-editor]")
    |> assert_has("[data-sequence-intervention]", text: "We take the eastern gate.", timeout: 20_000)
    |> assert_has("[data-stop-icon]")
    |> assert_has("[data-sequence-frame-outline]")
    |> click("[data-select-layer='#{context.layer.layer_key}']")
    |> assert_has("[data-layer-resize-handle='se']")
    |> click("[data-workspace-fullscreen]")
    |> assert_has("[data-flow-upper-workspace].fixed")
    |> click("[data-sequence-comments-toggle]")
    |> fill_in("#sequence-comment-body", "New thread", with: "Make the courtyard quieter.")
    |> click("#sequence-comment-send")
    |> assert_has("#sequence-comments-content", text: "Make the courtyard quieter.")
    |> click("#sequence-comments button[aria-label='Close comments']")
    |> click("[data-sequence-playback-toggle]")
    |> assert_has("[data-playback-dialogue]", text: "We take the eastern gate.")
    |> click("[data-playback-continue]")
    |> assert_has("[data-playback-dialogue]", text: "The courtyard is empty.")
    |> click("[data-playback-back]")
    |> assert_has("[data-playback-dialogue]", text: "We take the eastern gate.")
    |> click("[data-sequence-playback-toggle]")
    |> refute_has("[data-sequence-playback]")
    |> click("[data-workspace-fullscreen]")
    |> click("[data-toggle-visual-editor]")
    |> refute_has("[data-sequence-workspace]")
    |> assert_has("[data-play-icon]")
    |> assert_path(context.path)
  end

  test "resizes the workspace and keeps the executed scene above Debug", context do
    context.conn
    |> authenticate(context.user)
    |> visit(context.path)
    |> assert_has("[data-toggle-visual-editor]", timeout: 20_000)
    |> click("[data-flow-comment-node='#{context.first.id}'] [data-testid='node']")
    |> click("[data-toggle-visual-editor]")
    |> assert_has("[data-sequence-workspace]")
    |> drag_pin("[data-flow-splitter]", 0, -35)
    |> assert_has("[data-sequence-frame-outline]")
    |> drag_pin("[data-sequence-resize='library']", 40, 0)
    |> click("[data-testid='flow-dock'] > .dock-item:last-child button")
    |> assert_has("[data-flow-workspace='debug']", timeout: 20_000)
    |> click("[data-debug-step]")
    |> assert_has("[data-sequence-intervention]", text: "We take the eastern gate.")
    |> click("[data-flow-workspace='debug'] [role='tab']", "Composition")
    |> assert_has("[data-debug-composition]", text: "Courtyard backdrop")
    |> click("[data-flow-workspace='debug'] button[title='Stop']")
    |> assert_has("[data-flow-workspace='canvas']")
    |> assert_has("[data-sequence-workspace]")
  end
end
