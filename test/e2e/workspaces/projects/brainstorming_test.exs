defmodule StoryarnWeb.E2E.BrainstormingTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Frame
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "use the keyboard to create, write, publish and find an idea after reload", %{conn: conn} do
    ctx = ideation_fixture()
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming"

    session =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#brainstorming-workspace", timeout: 20_000)
      |> activate("#new-brainstorming-session")
      |> fill_in("#session-title", "Session title", with: "A storm at the gates")
      |> activate("#brainstorming-session-form button[type='submit']")
      |> assert_has("#brainstorming-workspace h2", text: "A storm at the gates")
      |> refute_has("[role='dialog']")
      |> activate("#new-brainstorming-idea")
      |> fill_in("#new-idea-title", "Title", with: "The reluctant guard")
      |> fill_body("The guard recognizes the visitor but says nothing.")
      |> activate("#idea-composer button[type='submit']")
      |> assert_has("#idea-title", value: "The reluctant guard")
      |> refute_has("[role='dialog']")
      |> fill_in("#idea-title", "Title", with: "The silent guard")
      |> assert_has("aside", text: "Saved", timeout: 10_000)
      |> activate("button", "Publish this revision")
      |> activate("button", "Review selection")
      |> assert_has("[role='dialog']", text: "1 revisions ready to publish")
      |> activate("button", "Confirm publication")
      |> refute_has("[role='dialog']")

    {:ok, sessions} = Ideation.list_sessions(ctx.author, project.id)
    created = Enum.find(sessions, &(&1.title == "A storm at the gates"))
    {:ok, [idea]} = Ideation.list_ideas(ctx.peer, project.id, created.id)
    assert idea.title == "The silent guard"

    session
    |> visit("#{path}/#{created.id}")
    |> assert_has("#idea-card-#{idea.id}", text: "The silent guard", timeout: 20_000)
    |> activate("button[aria-label='List']")
    |> activate("#idea-card-#{idea.id}")
    |> assert_has("#idea-title", value: "The silent guard")
    |> activate("button", "Idea history")
    |> assert_has("aside details", text: "Revision 1")
  end

  defp activate(session, selector, text), do: activate(session, "#{selector}:has-text(#{inspect(text)})")

  defp activate(session, selector) do
    session = assert_has(session, "#{selector}:not([disabled])")
    {:ok, _} = Frame.press(session.frame_id, selector: selector, key: "Enter", timeout: 10_000)
    session
  end

  defp fill_body(session, text) do
    {:ok, _} =
      Frame.fill(session.frame_id, selector: "#idea-composer [contenteditable='true']", value: text, timeout: 10_000)

    session
  end
end
