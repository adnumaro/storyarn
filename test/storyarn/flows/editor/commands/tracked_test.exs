defmodule Storyarn.Flows.Editor.Commands.TrackedTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.FlowNode

  defmodule TestAnalyticsAdapter do
    @moduledoc false

    def capture(payload) do
      send(Process.get(:editor_tracked_test_pid), {:analytics_capture, payload})
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

    Process.put(:editor_tracked_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAnalyticsAdapter)

    on_exit(fn ->
      restore_env(:analytics_adapter, original_adapter)
      Process.delete(:editor_tracked_test_pid)
    end)

    %{flow: flow, project: project, scope: scope, user: user}
  end

  describe "node creation facts" do
    test "create emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      assert {:ok, node} =
               Editor.create_editor_node(
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
               Editor.create_editor_node(
                 scope,
                 flow,
                 %{type: "unknown", position_x: 0.0, position_y: 0.0},
                 "create"
               )

      refute_event("flow node created")
    end

    test "duplicate emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Source"}})

      assert {:ok, duplicate} = Editor.duplicate_editor_node(scope, flow, source)

      assert_event_once("flow node created", %{
        "creation_method" => "duplicate",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => duplicate.type,
        "project_id" => flow.project_id
      })

      invalid = %FlowNode{type: "unknown", data: %{}, position_x: 0.0, position_y: 0.0}
      assert {:error, _reason} = Editor.duplicate_editor_node(scope, flow, invalid)
      refute_event("flow node created")
    end

    test "sequence creation emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      assert {:ok, sequence} =
               Editor.create_editor_sequence(
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
               Editor.create_editor_sequence(scope, flow, %{name: ""}, "create")

      refute_event("flow node created")
    end

    test "wrapping a selection emits exactly once after success and never after error", %{
      flow: flow,
      scope: scope
    } do
      selected = node_fixture(flow)

      assert {:ok, sequence} =
               Editor.wrap_editor_selection(scope, flow, [selected.id], %{name: "Wrapped"})

      assert_event_once("flow node created", %{
        "creation_method" => "wrap_selection",
        "flow_id" => flow.id,
        "has_parent" => false,
        "node_type" => sequence.type,
        "project_id" => flow.project_id
      })

      assert {:error, :empty_selection} =
               Editor.wrap_editor_selection(scope, flow, [], %{})

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
      {:ok, sequence} = Editor.create_sequence(flow.id, %{name: "Stage"})
      image = image_asset_fixture(project, user)
      drain_analytics()

      assert {:ok, layer} =
               Editor.create_editor_sequence_visual_layer(
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
               Editor.create_editor_sequence_visual_layer(
                 scope,
                 flow,
                 dialogue.id,
                 %{kind: "backdrop", asset_id: image.id}
               )

      refute_event("sequence visual layer created")

      assert {:ok, updated_layer} =
               Editor.update_editor_sequence_visual_layer(
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

      assert {:ok, _deleted} = Editor.delete_sequence_visual_layer(updated_layer)

      assert {:error, :sequence_visual_layer_not_found} =
               Editor.update_editor_sequence_visual_layer(
                 scope,
                 flow,
                 sequence.id,
                 updated_layer,
                 %{opacity: 0.25}
               )

      refute_event("sequence visual layer updated")
    end

    test "track upsert emits once after success and never after error", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      {:ok, sequence} = Editor.create_sequence(flow.id, %{name: "Audio"})
      audio = audio_asset_fixture(project, user)
      drain_analytics()

      assert {:ok, _track} =
               Editor.upsert_editor_sequence_track(
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
               Editor.upsert_editor_sequence_track(
                 scope,
                 flow,
                 sequence.id,
                 "narration",
                 %{}
               )

      refute_event("sequence track updated")
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

  defp restore_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_env(key, value), do: Application.put_env(:storyarn, key, value)
end
