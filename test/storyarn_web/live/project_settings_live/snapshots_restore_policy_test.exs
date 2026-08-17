defmodule StoryarnWeb.ProjectSettingsLive.SnapshotsRestorePolicyTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning.RestorePolicy

  setup :register_and_log_in_user

  test "does not offer restore when the exact-restore policy is disabled", %{
    conn: conn,
    user: user
  } do
    previous = Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn -> Application.put_env(:storyarn, RestorePolicy, previous) end)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      Keyword.put(previous || [], :project_snapshot_restore, false)
    )

    project = user |> project_fixture() |> Repo.preload(:workspace)
    snapshot = full_project_snapshot_fixture(project)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsSnapshots")
    assert [serialized] = vue.props["snapshots"]
    assert serialized["id"] == snapshot.id
    assert serialized["canRestore"] == false
  end

  test "offers restore only for snapshots captured under the exact restore contract", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    legacy = full_project_snapshot_fixture(project, %{restore_contract_version: nil})
    current = full_project_snapshot_fixture(project)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    snapshots =
      view
      |> LiveVue.Test.get_vue(name: "live/project/settings/ProjectSettingsSnapshots")
      |> then(& &1.props["snapshots"])
      |> Map.new(&{&1["id"], &1})

    assert snapshots[legacy.id]["canRestore"] == false
    assert snapshots[current.id]["canRestore"] == true
  end
end
