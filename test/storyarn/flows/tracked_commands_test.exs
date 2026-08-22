defmodule Storyarn.Flows.TrackedCommandsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.TrackedCommands
  alias Storyarn.Flows.Versioning
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Flows.Versioning.SnapshotStorage

  defmodule TestAnalyticsAdapter do
    @moduledoc false

    def capture(payload) do
      send(Process.get(:tracked_commands_test_pid), {:analytics_capture, payload})
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

    Process.put(:tracked_commands_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAnalyticsAdapter)
    Application.put_env(:storyarn, RestorePolicy, flow_version_restore: true)

    on_exit(fn ->
      restore_env(:analytics_adapter, original_adapter)
      restore_env(RestorePolicy, original_restore_policy)
      Process.delete(:tracked_commands_test_pid)
    end)

    %{flow: flow, project: project, scope: scope, user: user}
  end

  describe "node creation facts" do
    test "create_node emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      assert {:ok, node} =
               TrackedCommands.create_node(
                 scope,
                 flow,
                 %{type: "dialogue", position_x: 10.0, position_y: 20.0},
                 "create"
               )

      assert_event_once("flow node created", %{
        "creation_method" => "create",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => node.type,
        "project_id" => flow.project_id
      })

      assert {:error, _reason} =
               TrackedCommands.create_node(
                 scope,
                 flow,
                 %{type: "unknown", position_x: 0.0, position_y: 0.0},
                 "create"
               )

      refute_event("flow node created")
    end

    test "duplicate_node emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Source"}})

      assert {:ok, duplicate} = TrackedCommands.duplicate_node(scope, flow, source)

      assert_event_once("flow node created", %{
        "creation_method" => "duplicate",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => duplicate.type,
        "project_id" => flow.project_id
      })

      invalid = %FlowNode{type: "unknown", data: %{}, position_x: 0.0, position_y: 0.0}
      assert {:error, _reason} = TrackedCommands.duplicate_node(scope, flow, invalid)
      refute_event("flow node created")
    end

    test "create_sequence emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      assert {:ok, sequence} =
               TrackedCommands.create_sequence(
                 scope,
                 flow,
                 %{position_x: 10.0, position_y: 20.0},
                 "create"
               )

      assert_event_once("flow node created", %{
        "creation_method" => "create",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => sequence.type,
        "project_id" => flow.project_id
      })

      assert {:error, _reason} =
               TrackedCommands.create_sequence(scope, flow, %{name: ""}, "create")

      refute_event("flow node created")
    end

    test "wrap_selection_in_sequence emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      selected = node_fixture(flow)

      assert {:ok, sequence} =
               TrackedCommands.wrap_selection_in_sequence(
                 scope,
                 flow,
                 [selected.id],
                 %{name: "Wrapped"}
               )

      assert_event_once("flow node created", %{
        "creation_method" => "wrap_selection",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => sequence.type,
        "project_id" => flow.project_id
      })

      assert {:error, :empty_selection} =
               TrackedCommands.wrap_selection_in_sequence(scope, flow, [], %{})

      refute_event("flow node created")
    end
  end

  describe "sequence composition facts" do
    test "visual-layer commands emit once after success and never after error", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      {:ok, sequence} = Flows.create_sequence(flow.id, %{name: "Stage"})
      image = image_asset_fixture(project, user)
      drain_analytics()

      assert {:ok, layer} =
               TrackedCommands.create_sequence_visual_layer(
                 scope,
                 flow,
                 sequence.id,
                 %{kind: "backdrop", asset_id: image.id}
               )

      assert_event_once("sequence visual layer created", %{
        "flow_id" => flow.id,
        "has_asset" => true,
        "layer_kind" => "backdrop",
        "project_id" => flow.project_id,
        "sequence_id" => sequence.id,
        "slot" => "full"
      })

      dialogue = node_fixture(flow)

      assert {:error, :sequence_not_found} =
               TrackedCommands.create_sequence_visual_layer(
                 scope,
                 flow,
                 dialogue.id,
                 %{kind: "backdrop", asset_id: image.id}
               )

      refute_event("sequence visual layer created")

      assert {:ok, updated_layer} =
               TrackedCommands.update_sequence_visual_layer(
                 scope,
                 flow,
                 sequence.id,
                 layer,
                 %{opacity: 0.5}
               )

      assert_event_once("sequence visual layer updated", %{
        "changed_asset" => false,
        "flow_id" => flow.id,
        "has_asset" => true,
        "layer_kind" => "backdrop",
        "project_id" => flow.project_id,
        "sequence_id" => sequence.id,
        "slot" => "full"
      })

      assert {:ok, _deleted} = Flows.delete_sequence_visual_layer(updated_layer)

      assert {:error, :sequence_visual_layer_not_found} =
               TrackedCommands.update_sequence_visual_layer(
                 scope,
                 flow,
                 sequence.id,
                 updated_layer,
                 %{opacity: 0.25}
               )

      refute_event("sequence visual layer updated")
    end

    test "upsert_sequence_track emits once after success and never after error", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      {:ok, sequence} = Flows.create_sequence(flow.id, %{name: "Audio"})
      audio = audio_asset_fixture(project, user)
      drain_analytics()

      assert {:ok, _track} =
               TrackedCommands.upsert_sequence_track(
                 scope,
                 flow,
                 sequence.id,
                 "music",
                 %{asset_id: audio.id, volume: Decimal.new("0.5")}
               )

      assert_event_once("sequence track updated", %{
        "changed_asset" => true,
        "changed_volume" => true,
        "flow_id" => flow.id,
        "has_asset" => true,
        "project_id" => flow.project_id,
        "sequence_id" => sequence.id,
        "track_kind" => "music"
      })

      assert {:error, :invalid_kind} =
               TrackedCommands.upsert_sequence_track(
                 scope,
                 flow,
                 sequence.id,
                 "narration",
                 %{}
               )

      refute_event("sequence track updated")
    end
  end

  describe "version facts" do
    test "create_named_version emits once after success and rejects a missing title without emitting", %{
      flow: flow,
      scope: scope
    } do
      assert {:ok, version} =
               TrackedCommands.create_named_version(scope, flow,
                 title: "Checkpoint",
                 skip_diff: true
               )

      register_snapshot_cleanup(version)

      assert_event_once("version created", %{
        "entity_type" => "flow",
        "project_id" => flow.project_id
      })

      assert {:error, :title_required} =
               TrackedCommands.create_named_version(scope, flow, title: "  ")

      refute_event("version created")
    end

    test "restore_version emits once after success and never after a foreign-version error", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      assert {:ok, target} = Versioning.create_version(flow, user.id, skip_diff: true)
      register_snapshot_cleanup(target)
      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Changed"})

      assert {:ok, restored} =
               TrackedCommands.restore_version(
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
               TrackedCommands.restore_version(
                 scope,
                 restored,
                 foreign_version,
                 user_id: user.id
               )

      refute_event("version restored")
    end

    test "UI interaction facts are each emitted exactly once", %{flow: flow, scope: scope} do
      assert :ok = TrackedCommands.record_version_panel_opened(scope, flow)

      assert_event_once("version panel opened", %{
        "entity_type" => "flow",
        "project_id" => flow.project_id
      })

      assert :ok = TrackedCommands.record_version_compared(scope, flow)

      assert_event_once("version compared", %{
        "entity_type" => "flow",
        "project_id" => flow.project_id
      })
    end
  end

  defp assert_event_once(event_name, expected_properties) do
    assert_receive {:analytics_capture, %{event: ^event_name, properties: properties}}

    assert Map.take(properties, Map.keys(expected_properties)) == expected_properties
    refute_receive {:analytics_capture, %{event: ^event_name}}, 20
  end

  defp refute_event(event_name) do
    refute_receive {:analytics_capture, %{event: ^event_name}}, 20
  end

  defp drain_analytics do
    receive do
      {:analytics_capture, _payload} -> drain_analytics()
    after
      0 -> :ok
    end
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
