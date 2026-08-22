defmodule StoryarnWeb.FlowLive.VersionViewerTest do
  use StoryarnWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Chapter One"})

    {:ok, version} = Flows.create_version(flow, user.id, title: "v1")

    %{project: project, flow: flow, version: version}
  end

  defp viewer_path(project, flow, version_number) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/versions/#{version_number}/viewer"
  end

  defp error_reason(view) do
    LiveVue.Test.get_vue(view, name: "live/versioning/viewer/VersionViewerError").props["reason"]
  end

  describe "a readable version" do
    test "renders the version canvas", %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} = live(conn, viewer_path(project, flow, 1))

      vue = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowCanvas")
      assert vue.component == "live/flow/show/FlowCanvas"
      assert vue.props["readonly"] == true
    end
  end

  describe "a version that cannot be shown" do
    test "stays in place instead of redirecting out of the compare iframe", %{
      conn: conn,
      project: project,
      flow: flow,
      version: version
    } do
      strip_checksum(version)

      # The regression: mount used to redirect to /workspaces, which rendered
      # the workspace dashboard inside the compare pane.
      assert {:ok, view, _html} = live(conn, viewer_path(project, flow, 1))
      assert error_reason(view) == "integrity"
    end

    test "reports a missing checksum as an integrity failure", %{
      conn: conn,
      project: project,
      flow: flow,
      version: version
    } do
      strip_checksum(version)

      {:ok, view, _html} = live(conn, viewer_path(project, flow, 1))

      assert error_reason(view) == "integrity"
      refute render(view) =~ "FlowCanvas"
    end

    test "reports a checksum mismatch as an integrity failure", %{
      conn: conn,
      project: project,
      flow: flow,
      version: version
    } do
      Repo.update_all(from_version(version), set: [checksum: String.duplicate("a", 64)])

      {:ok, view, _html} = live(conn, viewer_path(project, flow, 1))

      assert error_reason(view) == "integrity"
    end

    test "reports a version number that does not exist as not found", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      assert {:ok, view, _html} = live(conn, viewer_path(project, flow, 99))

      assert error_reason(view) == "not_found"
    end

    test "logs the underlying reason the pane cannot show", %{
      conn: conn,
      project: project,
      flow: flow,
      version: version
    } do
      strip_checksum(version)

      log =
        capture_log(fn ->
          {:ok, _view, _html} = live(conn, viewer_path(project, flow, 1))
        end)

      assert log =~ "Version viewer"
      assert log =~ "integrity"
      assert log =~ "invalid_expected_checksum"
    end
  end

  defp strip_checksum(version) do
    {1, _} = Repo.update_all(from_version(version), set: [checksum: nil])
  end

  defp from_version(%EntityVersionRecord{id: id}) do
    import Ecto.Query, only: [from: 2]

    from(v in EntityVersionRecord, where: v.id == ^id)
  end
end
