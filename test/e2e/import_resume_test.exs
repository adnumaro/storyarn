defmodule StoryarnWeb.E2E.ImportResumeTest do
  @moduledoc """
  Browser coverage for restoring a durable Yarn import after navigation.

  Run with: mix test test/e2e/import_resume_test.exs --include e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.VersioningFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts.Scope
  alias Storyarn.Flows
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet

  @moduletag :e2e

  @emberfall_fixture_root Path.expand("../fixtures/imports/yarn/emberfall", __DIR__)
  @emberfall_fixture_files [
    "Emberfall.yarnproject",
    "Dialogue/01_arrival.yarn",
    "Dialogue/02_market.yarn",
    "Dialogue/03_watchtower.yarn"
  ]
  @space_journey_fixture_root Path.expand("../fixtures/imports/yarn/space_journey", __DIR__)
  @space_journey_fixture_files ["SpaceJourney.yarnproject", "SpaceJourney_FinalVersion.yarn"]

  test "restores a completed import after navigation and reset does not resurrect it", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture(%{name: "Import Resume Project"}) |> Repo.preload(:workspace)
    yarn_path = space_journey_fixture()

    import_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/import"

    navigation_path = "/users/settings"
    resume_storage_key = Imports.resume_storage_key(Scope.for_user(user), project)

    session =
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
      |> assert_has("[data-testid='yarn-import-speaker-decision']")
      |> select_space_journey_speaker_actions()
      |> assert_has("#yarn-import-review-acknowledgement")
      |> click("#yarn-import-review-acknowledgement")
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

    session
    |> assert_has("[data-testid='yarn-import-reset']")
    |> click("[data-testid='yarn-import-reset']")
    |> assert_has("#yarn-import-file-picker")
    |> assert_attempt_reference_cleared(resume_storage_key)
    |> visit(navigation_path)
    |> assert_has("#profile-display-name")
    |> visit(import_path)
    |> assert_has("#yarn-import-file-picker")
    |> refute_has("span", text: "The Yarn project was imported successfully.")

    flows_by_name = Map.new(Flows.list_flows(project.id), &{&1.name, &1})
    assert flows_by_name["Start"].is_main

    flow_index_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"

    session
    |> visit(flow_index_path)
    |> assert_has("a", text: "Start")
    |> assert_has("a", text: "TalkToCaptain")
    |> assert_has("a", text: "TalkToEngineer")
    |> assert_has("a", text: "TalkToCrewmate")
    |> assert_has("a", text: "BridgeEnding")
    |> assert_has("[data-slot='badge']", text: "Main")
    |> visit("#{flow_index_path}/#{flows_by_name["Start"].id}")
    |> assert_has("[id^='flow-canvas-']")
    |> assert_has("[data-testid='node']", text: "Another day in Space Fleet.")
    |> assert_has("[data-testid='node']", text: "Go and talk to the Captain")
    |> visit("#{flow_index_path}/#{flows_by_name["BridgeEnding"].id}")
    |> assert_has("[data-testid='node']", text: "We're totally doomed. It's the Space Pirates!")
  end

  test "resumes a replacement while its recovery snapshot is pending and links to recovery", %{conn: conn} do
    user = user_fixture()

    project =
      user
      |> project_fixture(%{name: "Emberfall Replacement Project"})
      |> Repo.preload(:workspace)

    old_sheet = sheet_fixture(project, %{name: "Previous campaign notes"})
    yarn_path = yarn_project_fixture()

    import_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/import"

    recovery_path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"

    navigation_path = "/users/settings"

    session =
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
      |> assert_has("[data-testid='yarn-import-mode-selector']")
      |> click("[data-testid='yarn-import-mode-replace'] [role='radio']")
      |> assert_has("#yarn-import-confirm", text: "Replace project content")
      |> select_suggested_speaker_actions()
      |> assert_has("#yarn-import-review-acknowledgement")
      |> click("#yarn-import-review-acknowledgement")
      |> assert_has("#yarn-import-validate:not([disabled])")
      |> click("#yarn-import-validate")
      |> assert_has("#yarn-import-confirm:not([disabled])")
      |> click("#yarn-import-confirm")
      |> assert_has("button", text: "Create snapshot and replace")
      |> click_button("Create snapshot and replace")
      |> assert_has("[data-testid='yarn-import-awaiting-snapshot']")
      |> visit(navigation_path)
      |> assert_has("#profile-display-name")
      |> visit(import_path)
      |> assert_has("[data-testid='yarn-import-awaiting-snapshot']")
      |> visit(navigation_path)
      |> unwrap(fn _browser ->
        queued = latest_active_attempt(project.id, user.id)

        assert {:ok, completed} =
                 Imports.perform_import(queued.id,
                   attempt: 1,
                   max_attempts: 3,
                   snapshot_request: ready_snapshot_request(user, current_project_checksum(project))
                 )

        assert completed.status == "completed"
        assert Repo.get!(Sheet, old_sheet.id).deleted_at
      end)

    completed =
      Repo.one!(
        from attempt in ProjectImportAttempt,
          where: attempt.project_id == ^project.id and attempt.status == "completed",
          order_by: [desc: attempt.id],
          limit: 1
      )

    snapshot_id = completed.pre_import_snapshot_id
    assert is_integer(snapshot_id)
    recovery_href = "#{recovery_path}#snapshot-#{snapshot_id}"

    session =
      session
      |> visit(import_path)
      |> assert_has("span", text: "The Yarn project replaced the previous narrative content successfully.")
      |> assert_has(
        "[data-testid='yarn-import-recovery-snapshot-link'][href='#{recovery_href}']",
        text: "View recovery snapshot"
      )

    session
    |> click("[data-testid='yarn-import-recovery-snapshot-link']")
    |> assert_path(recovery_path)
    |> evaluate("window.location.hash", fn hash ->
      assert hash == "#snapshot-#{snapshot_id}"
    end)
    |> assert_has("#snapshot-#{snapshot_id}")
    |> assert_has("[data-testid='snapshot-card-#{snapshot_id}']")
  end

  defp select_suggested_speaker_actions(session) do
    evaluate(
      session,
      """
      (() => {
        const actions = Array.from(
          document.querySelectorAll('[data-testid="yarn-import-action-create-sheet"]')
        );

        actions.forEach((action) => action.click());
        return actions.length;
      })()
      """,
      fn count -> assert count == 5 end
    )
  end

  defp select_space_journey_speaker_actions(session) do
    evaluate(
      session,
      """
      (() => {
        const decisions = Array.from(
          document.querySelectorAll('[data-testid="yarn-import-speaker-decision"]')
        );

        return decisions.map((decision) => {
          const speaker = decision.querySelector('p[id^="yarn-speaker-"]')?.textContent?.trim();
          const action = speaker === 'Crewemate'
            ? 'yarn-import-action-preserve-literal'
            : 'yarn-import-action-create-sheet';

          decision.querySelector(`[data-testid="${action}"]`)?.click();
          return [speaker, action];
        });
      })()
      """,
      fn selections ->
        assert length(selections) == 6
        assert ["Crewemate", "yarn-import-action-preserve-literal"] in selections
      end
    )
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

  defp yarn_project_fixture do
    archive_fixture("storyarn-emberfall", @emberfall_fixture_root, @emberfall_fixture_files)
  end

  defp space_journey_fixture do
    archive_fixture(
      "storyarn-space-journey",
      @space_journey_fixture_root,
      @space_journey_fixture_files
    )
  end

  defp archive_fixture(name, root, relative_paths) do
    filename = "#{name}-#{System.unique_integer([:positive])}.zip"
    path = Path.join(System.tmp_dir!(), filename)

    entries =
      Enum.map(relative_paths, fn relative_path ->
        source_path = Path.join(root, relative_path)
        {String.to_charlist(relative_path), File.read!(source_path)}
      end)

    {:ok, {_name, archive}} = :zip.create(String.to_charlist(filename), entries, [:memory])
    File.write!(path, archive)
    on_exit(fn -> File.rm(path) end)

    path
  end

  defp ready_snapshot_request(user, checksum) do
    fn _scope, project, attrs ->
      {:ok,
       full_project_snapshot_fixture(project, %{
         created_by_id: user.id,
         idempotency_key: attrs.idempotency_key,
         project_checksum: checksum,
         asset_blob_size_bytes: 0
       })}
    end
  end

  defp current_project_checksum(project) do
    assert {:ok, checksum} =
             Repo.transact(fn ->
               assets = Assets.list_assets_for_export(project.id)
               {asset_blob_hashes, asset_metadata} = AssetHashResolver.capture_catalog_maps(assets)

               snapshot =
                 project.id
                 |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(
                   localization_scope: :active,
                   include_referenced_tombstones: true
                 )
                 |> Map.put(
                   "asset_restore_contract_version",
                   AssetHashResolver.exact_restore_contract_version()
                 )
                 |> Map.put("asset_blob_hashes", asset_blob_hashes)
                 |> Map.put("asset_metadata", asset_metadata)

               SnapshotArchiveStorage.canonical_project_checksum(snapshot, assets)
             end)

    checksum
  end
end
