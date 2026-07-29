defmodule StoryarnWeb.E2E.CommandPaletteTest do
  @moduledoc """
  Real-dialog coverage for the authenticated command palette.

  Run with: mix test.e2e test/e2e/command_palette_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
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
    |> refute_has("[data-slot='dialog-content'] [role='status']", timeout: 20_000)
    |> assert_has(
      "[data-operation-id='create'][data-operation-available='false']",
      text: "Requires edit access to at least one project."
    )
    |> assert_has(
      "[data-operation-id='run_command'][data-operation-available='false']",
      text: "No commands are available in this view."
    )
    |> assert_has("[data-operation-id='open_view'][data-operation-available='true']")
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
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> refute_has("[data-slot='dialog-content'] [role='status']", timeout: 20_000)
    |> assert_has("[data-slot='command-item']", text: "New Sheet", timeout: 20_000)
    |> click("[data-slot='command-item']", "New Sheet")
    |> assert_has("[data-slot='command-input'][placeholder='Create in project…']")
    |> evaluate(active_palette_input_expression(), fn active? -> assert active? end)
    |> evaluate(escape_from_palette_expression())
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> assert_has("[data-slot='command-item']", text: "New Sheet")
  end

  test "generated help opens the guided goto operation and navigates on explicit submit",
       %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture(%{name: "Veilbreak"}) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Chapter Two"})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"

    conn
    |> authenticate(user)
    |> visit(path)
    |> wait_for_palette()
    |> evaluate(open_palette_expression())
    |> refute_has("[data-slot='dialog-content'] [role='status']", timeout: 20_000)
    |> assert_has("[data-operation-id='goto']", text: "Go to…")
    |> click("[data-operation-id='goto']")
    |> assert_has("[data-slot='palette-operation-input'] input[aria-label='destination']")
    |> fill_in("[data-slot='palette-operation-input'] input", "destination", with: "Chapter Two")
    |> assert_has("[data-slot='command-item']", text: "Chapter Two", timeout: 20_000)
    |> click("[data-slot='command-item']", "Chapter Two")
    |> evaluate(selected_operation_value_expression("Chapter Two"), fn visible? -> assert visible? end)
    |> assert_has("[data-slot='command-item']", text: "Run operation")
    |> click("[data-slot='command-item']", "Run operation")
    |> assert_path("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
  end

  test "the reference-pattern door opens the exact variable definition", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture(%{name: "Veilbreak"}) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 42},
        variable_name: "health"
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    conn
    |> authenticate(user)
    |> visit(path)
    |> wait_for_palette()
    |> evaluate(open_palette_expression())
    |> fill_in("[data-slot='command-input']", "Type a command or search…", with: "?health")
    |> assert_has("[data-lookup-result-id]", text: "mc.jaime.health", timeout: 20_000)
    |> click("[data-lookup-result-id]", "mc.jaime.health")
    |> assert_path(path)
    |> evaluate("window.location.search", fn search ->
      assert search == "?highlight=block:#{block.id}"
    end)
    |> assert_has("#sheet-block-#{block.id}.ring-2", timeout: 5_000)
  end

  defp wait_for_palette(conn) do
    conn
    |> assert_has("body .phx-connected")
    |> unwrap(fn %{frame_id: frame_id} ->
      assert {:ok, _element} =
               PlaywrightEx.Frame.wait_for_selector(frame_id,
                 selector: "#command-palette-island[data-v-app] [data-command-palette-ready='true']",
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

  defp selected_operation_value_expression(value) do
    encoded_value = Jason.encode!(value)

    "document.querySelector(\"[data-slot='palette-operation-input'] input\")?.value === #{encoded_value}"
  end
end
