defmodule StoryarnWeb.E2E.OnboardingTest do
  @moduledoc """
  E2E tests for automatic onboarding and its explicit opt-out.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts.Scope
  alias Storyarn.Onboarding
  alias Storyarn.Workspaces

  @moduletag :e2e

  test "dismissal without opt-out only snoozes the tutorial for the browser session", %{conn: conn} do
    user = user_fixture()
    workspace = Workspaces.get_default_workspace(user)
    path = "/workspaces/#{workspace.slug}"

    conn =
      conn
      |> authenticate(user, onboarding: :pending)
      |> visit(path)
      |> assert_has("[data-testid='onboarding-not-now']")
      |> click("[data-testid='onboarding-not-now']")
      |> refute_has("[data-testid='onboarding-not-now']")
      |> visit(path)
      |> refute_has("[data-testid='onboarding-not-now']")

    assert Onboarding.summary(Scope.for_user(user)).guides["workspace"].state == :pending

    conn
    |> evaluate("window.sessionStorage.clear()")
    |> visit(path)
    |> assert_has("[data-testid='onboarding-not-now']")
  end

  test "explicit opt-out prevents the tutorial from opening in future sessions", %{conn: conn} do
    user = user_fixture()
    workspace = Workspaces.get_default_workspace(user)
    path = "/workspaces/#{workspace.slug}"

    conn =
      conn
      |> authenticate(user, onboarding: :pending)
      |> visit(path)
      |> assert_has("[data-testid='onboarding-dont-show-again']")
      |> click("[data-testid='onboarding-dont-show-again']")
      |> click("[data-testid='onboarding-not-now']")
      |> refute_has("[data-testid='onboarding-not-now']")

    wait_for_tutorial_state(user, "workspace", :completed)

    conn
    |> evaluate("window.sessionStorage.clear()")
    |> visit(path)
    |> refute_has("[data-testid='onboarding-not-now']")
    |> click_button("New Project")
    |> assert_has("[data-slot='dialog-content'] h2", text: "New Project")
  end

  defp wait_for_tutorial_state(user, tutorial, expected_state, attempts \\ 20)

  defp wait_for_tutorial_state(user, tutorial, expected_state, 0) do
    actual_state = Onboarding.summary(Scope.for_user(user)).guides[tutorial].state

    flunk("Expected #{tutorial} tutorial to be #{expected_state}, got #{actual_state}")
  end

  defp wait_for_tutorial_state(user, tutorial, expected_state, attempts) do
    if Onboarding.summary(Scope.for_user(user)).guides[tutorial].state == expected_state do
      :ok
    else
      Process.sleep(50)
      wait_for_tutorial_state(user, tutorial, expected_state, attempts - 1)
    end
  end
end
