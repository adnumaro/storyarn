defmodule StoryarnWeb.ProjectSettingsLive.SnapshotsRolloutTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshotBuild

  setup :register_and_log_in_user

  test "reports the archive write fence without queuing a snapshot", %{conn: conn, user: user} do
    original = Application.get_env(:storyarn, ProjectSnapshotBuild, [])

    Application.put_env(
      :storyarn,
      ProjectSnapshotBuild,
      Keyword.put(original, :archive_writes_enabled, false)
    )

    on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotBuild, original) end)

    project = user |> project_fixture() |> Repo.preload(:workspace)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/snapshots"
      )

    render_click(view, "create_snapshot", %{
      "mode" => "full",
      "idempotency_key" => Ecto.UUID.generate(),
      "title" => "Fenced request",
      "description" => "Must remain empty"
    })

    assert_push_event(view, "snapshot_request_failed", %{
      reason: "rollout_not_enabled",
      requiredBytes: nil,
      availableBytes: nil,
      used: nil,
      limit: nil
    })

    vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsSnapshots")
    assert vue.props["snapshots"] == []
    assert Repo.aggregate(Storyarn.Versioning.ProjectSnapshot, :count) == 0
  end
end
