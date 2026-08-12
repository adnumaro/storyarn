defmodule StoryarnWeb.E2E.ImportResumeTest do
  @moduledoc """
  Browser coverage for restoring a durable Yarn import after navigation.

  Run with: mix test test/e2e/import_resume_test.exs --include e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts.Scope
  alias Storyarn.Imports
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Repo

  @moduletag :e2e

  test "restores a completed import after navigation and reset does not resurrect it", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture(%{name: "Import Resume Project"}) |> Repo.preload(:workspace)
    yarn_path = yarn_fixture()

    import_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"

    navigation_path = "/users/settings"
    resume_storage_key = Imports.resume_storage_key(Scope.for_user(user), project)

    conn
    |> authenticate(user)
    |> visit(import_path)
    |> assert_has("#yarn-import-file-picker")
    |> unwrap(fn %{frame_id: frame_id} ->
      {:ok, _} =
        PlaywrightEx.Frame.set_input_files(frame_id,
          selector: "input[name='import_file']",
          local_paths: [yarn_path],
          timeout: 10_000
        )
    end)
    |> assert_has("span", text: Path.basename(yarn_path))
    |> click("#yarn-import-preview")
    |> assert_has("#yarn-import-validate:not([disabled])")
    |> click("#yarn-import-validate")
    |> assert_has("#yarn-import-confirm:not([disabled])")
    |> click("#yarn-import-confirm")
    |> assert_has("[data-testid='yarn-import-processing']")
    |> assert_attempt_reference_matches_latest(project.id, user.id, resume_storage_key)
    |> visit(navigation_path)
    |> assert_has("#profile-display-name")
    |> unwrap(fn _browser ->
      queued = latest_active_attempt(project.id, user.id)

      assert {:ok, completed} =
               Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      assert completed.status == "completed"
    end)
    |> visit(import_path)
    |> assert_has("span", text: "The Yarn project was imported successfully.")
    |> assert_has("[data-testid='yarn-import-reset']")
    |> click("[data-testid='yarn-import-reset']")
    |> assert_has("#yarn-import-file-picker")
    |> assert_attempt_reference_cleared(resume_storage_key)
    |> visit(navigation_path)
    |> assert_has("#profile-display-name")
    |> visit(import_path)
    |> assert_has("#yarn-import-file-picker")
    |> refute_has("span", text: "The Yarn project was imported successfully.")
  end

  defp assert_attempt_reference_matches_latest(session, project_id, user_id, resume_storage_key) do
    attempt = latest_active_attempt(project_id, user_id)
    attempt_storage_key = "#{resume_storage_key}:attempt:#{attempt.id}"

    evaluate(
      session,
      """
      key => JSON.parse(window.localStorage.getItem(key))
      """,
      [is_function: true, arg: attempt_storage_key],
      fn stored ->
        assert stored["version"] == 1
        assert stored["attemptId"] == attempt.id
        assert is_number(stored["savedAt"])
      end
    )
  end

  defp assert_attempt_reference_cleared(session, resume_storage_key) do
    evaluate(
      session,
      """
      namespace => Object.keys(window.localStorage).filter(
        key => key === namespace || key.startsWith(`${namespace}:attempt:`)
      )
      """,
      [is_function: true, arg: resume_storage_key],
      fn keys -> assert keys == [] end
    )
  end

  defp latest_active_attempt(project_id, user_id) do
    Repo.one!(
      from attempt in ProjectImportAttempt,
        where:
          attempt.project_id == ^project_id and attempt.user_id == ^user_id and
            attempt.status in ["ready", "queued", "running", "retrying"],
        order_by: [desc: attempt.id],
        limit: 1
    )
  end

  defp yarn_fixture do
    filename = "storyarn-import-resume-#{System.unique_integer([:positive])}.yarn"
    path = Path.join(System.tmp_dir!(), filename)

    File.write!(path, "title: Resume Start\n---\nHello after navigation\n===\n")
    on_exit(fn -> File.rm(path) end)

    path
  end
end
