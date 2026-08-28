defmodule Storyarn.Flows.Versioning.Commands.TrackedTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.Versioning
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Flows.Versioning.SnapshotStorage

  defmodule TestAnalyticsAdapter do
    @moduledoc false

    def capture(payload) do
      send(Process.get(:versioning_tracked_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(_payload), do: :ok
  end

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    scope = user_scope_fixture(user)
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)
    original_restore_policy = Application.get_env(:storyarn, RestorePolicy)

    Process.put(:versioning_tracked_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAnalyticsAdapter)
    Application.put_env(:storyarn, RestorePolicy, flow_version_restore: true)

    on_exit(fn ->
      restore_env(:analytics_adapter, original_adapter)
      restore_env(RestorePolicy, original_restore_policy)
      Process.delete(:versioning_tracked_test_pid)
    end)

    %{flow: flow, project: project, scope: scope, user: user}
  end

  test "named-version creation emits once after success and never after a missing title", %{
    flow: flow,
    scope: scope
  } do
    assert {:ok, version} =
             Versioning.create_named_version(scope, flow,
               title: "Checkpoint",
               skip_diff: true
             )

    register_snapshot_cleanup(version)

    assert_event_once("version created", %{
      "entity_type" => "flow",
      "project_id" => flow.project_id
    })

    assert {:error, :title_required} =
             Versioning.create_named_version(scope, flow, title: "  ")

    refute_event("version created")
  end

  test "restore emits once after success and never after a foreign-version error", %{
    flow: flow,
    project: project,
    scope: scope,
    user: user
  } do
    assert {:ok, target} = Versioning.create_version(flow, user.id, skip_diff: true)
    register_snapshot_cleanup(target)
    assert {:ok, changed} = Editor.update_flow(flow, %{name: "Changed"})

    assert {:ok, restored} =
             Versioning.restore_tracked_version(
               scope,
               changed,
               target,
               user_id: user.id
             )

    register_flow_snapshot_cleanup(flow.id)

    assert_event_once("version restored", %{
      "entity_type" => "flow",
      "project_id" => flow.project_id
    })

    other_flow = flow_fixture(project)
    assert {:ok, foreign_version} = Versioning.create_version(other_flow, user.id, skip_diff: true)
    register_snapshot_cleanup(foreign_version)

    assert {:error, :entity_version_scope_mismatch} =
             Versioning.restore_tracked_version(
               scope,
               restored,
               foreign_version,
               user_id: user.id
             )

    refute_event("version restored")
  end

  test "UI interaction facts are each emitted exactly once", %{flow: flow, scope: scope} do
    assert :ok = Versioning.record_version_panel_opened(scope, flow)

    assert_event_once("version panel opened", %{
      "entity_type" => "flow",
      "project_id" => flow.project_id
    })

    assert :ok = Versioning.record_version_compared(scope, flow)

    assert_event_once("version compared", %{
      "entity_type" => "flow",
      "project_id" => flow.project_id
    })
  end

  defp assert_event_once(event_name, expected_properties) do
    assert_receive {:analytics_capture, %{event: ^event_name, properties: properties}}

    assert Map.take(properties, Map.keys(expected_properties)) == expected_properties
    refute_receive {:analytics_capture, %{event: ^event_name}}, 20
  end

  defp refute_event(event_name) do
    refute_receive {:analytics_capture, %{event: ^event_name}}, 20
  end

  defp register_flow_snapshot_cleanup(flow_id) do
    flow_id
    |> Versioning.list_versions()
    |> Enum.each(&register_snapshot_cleanup/1)
  end

  defp register_snapshot_cleanup(version) do
    on_exit(fn -> SnapshotStorage.delete(version.storage_key) end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_env(key, value), do: Application.put_env(:storyarn, key, value)
end
