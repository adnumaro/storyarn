defmodule StoryarnWeb.E2E.CommandPaletteTest do
  @moduledoc """
  Real-dialog coverage for the authenticated command palette.

  Run with: mix test.e2e test/e2e/command_palette_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Repo

  @moduletag :e2e

  test "is available in settings and the shortcut closes from its focused input", %{conn: conn} do
    conn
    |> authenticate(user_fixture())
    |> visit("/users/settings")
    |> wait_for_palette()
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> evaluate(active_palette_input_expression(), fn active? -> assert active? end)
    |> evaluate(close_palette_from_input_expression())
    |> refute_has("[data-slot='dialog-content'] [data-slot='command-input']")
  end

  test "Escape goes back one step and restores focus with the real Reka dialog", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture(%{name: "Veilbreak"}) |> Repo.preload(:workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"

    conn
    |> authenticate(user)
    |> visit(path)
    |> wait_for_palette()
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='command-item']", text: "New Sheet")
    |> click("[data-slot='command-item']", "New Sheet")
    |> assert_has("[data-slot='command-input'][placeholder='Create in project…']")
    |> evaluate(active_palette_input_expression(), fn active? -> assert active? end)
    |> evaluate(escape_from_palette_expression())
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> assert_has("[data-slot='command-item']", text: "New Sheet")
  end

  defp wait_for_palette(conn) do
    conn
    |> assert_has("body .phx-connected")
    |> unwrap(fn %{frame_id: frame_id} ->
      assert {:ok, _element} =
               PlaywrightEx.Frame.wait_for_selector(frame_id,
                 selector: "#command-palette-island[data-v-app]",
                 state: "attached",
                 timeout: 10_000
               )
    end)
  end

  defp open_palette_expression do
    "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'k', ctrlKey: true, bubbles: true, cancelable: true}))"
  end

  defp close_palette_from_input_expression do
    "document.activeElement?.dispatchEvent(new KeyboardEvent('keydown', {key: 'k', ctrlKey: true, bubbles: true, cancelable: true}))"
  end

  defp escape_from_palette_expression do
    "document.activeElement?.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true, cancelable: true}))"
  end

  defp active_palette_input_expression do
    "document.activeElement?.getAttribute('data-slot') === 'command-input'"
  end
end
