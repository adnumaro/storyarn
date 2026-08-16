defmodule StoryarnWeb.ProjectSettingsLive.SnapshotsRestorePolicyTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotContentHealth

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

  test "serializes captured restore blockers with a safe actionable location", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    content_health =
      SnapshotContentHealth.build([
        %{
          code: :localization_speaker_mismatch,
          severity: :warning,
          entity_type: :flow_node,
          entity_id: 101,
          source_field: "speaker_sheet_id",
          impact: :restore_blocked,
          container_type: :flow,
          container_id: 42
        }
      ])

    snapshot = full_project_snapshot_fixture(project, %{content_health: content_health})

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    serialized =
      view
      |> LiveVue.Test.get_vue(name: "live/project/settings/ProjectSettingsSnapshots")
      |> then(&Enum.find(&1.props["snapshots"], fn item -> item["id"] == snapshot.id end))

    assert serialized["canRestore"] == false
    assert serialized["restoreBlockedByContentIssues"] == true
    assert serialized["downloadUrl"] =~ "/snapshots/#{snapshot.id}/download"
    assert serialized["contentHealth"]["impact_counts"]["restore_blocked"] == 1

    assert [issue] = serialized["contentHealth"]["issues"]
    assert issue["code"] == "localization_speaker_mismatch"

    assert issue["locationUrl"] ==
             "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/42"

    refute Map.has_key?(issue, "details")
  end

  test "keeps an unassessed historical snapshot downloadable but disables restore", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    snapshot =
      full_project_snapshot_fixture(project, %{
        content_health: SnapshotContentHealth.unknown()
      })

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    serialized =
      view
      |> LiveVue.Test.get_vue(name: "live/project/settings/ProjectSettingsSnapshots")
      |> then(&Enum.find(&1.props["snapshots"], fn item -> item["id"] == snapshot.id end))

    assert serialized["canRestore"] == false
    assert serialized["restoreBlockedByContentIssues"] == true
    assert serialized["contentHealth"]["state"] == "unknown"
    assert serialized["downloadUrl"] =~ "/snapshots/#{snapshot.id}/download"
  end

  test "runtime degradation remains visible without disabling exact restore", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)

    content_health =
      SnapshotContentHealth.build([
        %{
          code: :invalid_project_snapshot_main_flow_count,
          severity: :warning,
          entity_type: :project,
          entity_id: project.id,
          impact: :runtime_degraded,
          container_type: :project,
          container_id: project.id
        }
      ])

    snapshot = full_project_snapshot_fixture(project, %{content_health: content_health})

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    serialized =
      view
      |> LiveVue.Test.get_vue(name: "live/project/settings/ProjectSettingsSnapshots")
      |> then(&Enum.find(&1.props["snapshots"], fn item -> item["id"] == snapshot.id end))

    assert serialized["canRestore"] == true
    assert serialized["restoreBlockedByContentIssues"] == false
    assert serialized["contentHealth"]["impact_counts"]["runtime_degraded"] == 1
  end
end
