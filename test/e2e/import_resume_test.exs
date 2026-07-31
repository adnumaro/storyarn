defmodule StoryarnWeb.E2E.ImportResumeTest do
  @moduledoc """
  Browser coverage for restoring a durable Yarn import after navigation.

  Run with: mix test test/e2e/import_resume_test.exs --include e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts.Scope
  alias Storyarn.Imports
  alias Storyarn.Repo

  @moduletag :e2e

  test "restores a completed import after navigation and reset does not resurrect it", %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    project = user |> project_fixture(%{name: "Import Resume Project"}) |> Repo.preload(:workspace)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               scope,
               project,
               "resume-project.yarn",
               "title: Resume Start\n---\nHello after navigation\n===\n"
             )

    assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)

    import_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"

    project_path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"

    conn
    |> authenticate(user)
    |> visit(import_path)
    |> assert_has("[data-testid='yarn-import-processing']")
    |> store_attempt_reference(project.id, user.id, queued.id)
    |> visit(project_path)
    |> assert_has("[data-testid='project-stat-flows']")
    |> unwrap(fn _browser ->
      assert {:ok, completed} =
               Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      assert completed.status == "completed"
    end)
    |> visit(import_path)
    |> assert_has("span", text: "The Yarn project was imported successfully.")
    |> assert_has("[data-testid='yarn-import-reset']")
    |> click("[data-testid='yarn-import-reset']")
    |> assert_has("#yarn-import-file-picker")
    |> assert_attempt_reference_cleared(project.id, user.id)
    |> visit(project_path)
    |> assert_has("[data-testid='project-stat-flows']")
    |> visit(import_path)
    |> assert_has("#yarn-import-file-picker")
    |> refute_has("span", text: "The Yarn project was imported successfully.")
  end

  defp store_attempt_reference(session, project_id, user_id, attempt_id) do
    evaluate(
      session,
      """
      ({ key, attemptId }) => {
        window.localStorage.setItem(
          key,
          JSON.stringify({ version: 1, attemptId, savedAt: Date.now() })
        );
      }
      """,
      is_function: true,
      arg: %{
        "key" => storage_key(project_id, user_id),
        "attemptId" => attempt_id
      }
    )
  end

  defp assert_attempt_reference_cleared(session, project_id, user_id) do
    evaluate(
      session,
      "key => window.localStorage.getItem(key)",
      [is_function: true, arg: storage_key(project_id, user_id)],
      fn value -> assert is_nil(value) end
    )
  end

  # Scoped to the signed-in user as well as the project, so a shared browser
  # cannot hand one member's in-flight attempt to the next.
  defp storage_key(project_id, user_id), do: "storyarn:project-import:#{project_id}:#{user_id}"
end
