defmodule Storyarn.Flows.Editor.Commands.TrackedTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceVisualLayer

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

  describe "composition owner duplication" do
    test "duplicates a dialogue with its parent, source, local layers, and local tracks", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      {:ok, parent} = Editor.create_sequence(flow.id, %{name: "Canvas parent"})
      {:ok, composition_source} = Editor.create_sequence(flow.id, %{name: "Composition source"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          position_x: 120.0,
          position_y: 240.0,
          parent_id: parent.id,
          composition_source_id: composition_source.id,
          data: %{
            "text" => "<p>Hold the gate.</p>",
            "technical_id" => "hold-the-gate",
            "localization_id" => "dialogue-original"
          }
        })

      image = image_asset_fixture(project, user)
      removed_image = image_asset_fixture(project, user)
      audio = audio_asset_fixture(project, user)
      removed_audio = audio_asset_fixture(project, user)

      {:ok, inherited_layer} =
        Editor.create_sequence_visual_layer(composition_source.id, %{
          asset_id: image.id,
          kind: "character",
          label: "Guard",
          slot: "bottom-right",
          opacity: 0.7
        })

      {:ok, removed_layer} =
        Editor.create_sequence_visual_layer(composition_source.id, %{
          asset_id: removed_image.id,
          kind: "prop"
        })

      {:ok, inherited_track} =
        Editor.upsert_sequence_track(composition_source.id, "ambience", %{
          asset_id: audio.id,
          position: 2,
          volume: Decimal.new("0.350")
        })

      {:ok, removed_track} =
        Editor.upsert_sequence_track(composition_source.id, "sfx", %{
          asset_id: removed_audio.id
        })

      {:ok, _patch} =
        Editor.override_sequence_visual_layer(dialogue.id, inherited_layer.layer_key, %{
          opacity: 0.45
        })

      {:ok, _tombstone} =
        Editor.remove_sequence_visual_layer(dialogue.id, removed_layer.layer_key)

      {:ok, _patch} =
        Editor.override_sequence_track(dialogue.id, inherited_track.track_key, %{
          volume: Decimal.new("0.200")
        })

      {:ok, _tombstone} = Editor.remove_sequence_track(dialogue.id, removed_track.track_key)

      drain_analytics()

      assert {:ok, duplicate} = Editor.duplicate_editor_node(scope, flow, dialogue)

      assert duplicate.type == "dialogue"
      assert duplicate.parent_id == parent.id
      assert duplicate.composition_source_id == composition_source.id
      assert duplicate.position_x == 170.0
      assert duplicate.position_y == 290.0
      assert duplicate.data["text"] == dialogue.data["text"]
      assert duplicate.data["technical_id"] == ""
      assert duplicate.data["localization_id"] != dialogue.data["localization_id"]
      assert visual_state(duplicate.id) == visual_state(dialogue.id)
      assert track_state(duplicate.id) == track_state(dialogue.id)

      assert_event_once("flow node created", %{
        "creation_method" => "duplicate",
        "flow_id" => flow.id,
        "has_parent" => true,
        "node_type" => "dialogue",
        "project_id" => flow.project_id
      })
    end

    test "duplicates a sequence with its complete local composition and config", %{
      flow: flow,
      project: project,
      scope: scope,
      user: user
    } do
      {:ok, parent} = Editor.create_sequence(flow.id, %{name: "Canvas parent"})
      composition_source = node_fixture(flow, %{data: %{"text" => "Previous shot"}})

      {:ok, sequence} =
        Editor.create_sequence(flow.id, %{
          name: "Throne room",
          position_x: 10.0,
          position_y: 20.0,
          parent_id: parent.id,
          width: 640.0,
          height: 360.0
        })

      {:ok, sequence} = Editor.set_composition_source(sequence.id, composition_source.id)
      image = image_asset_fixture(project, user)
      audio = audio_asset_fixture(project, user)

      {:ok, _layer} =
        Editor.create_sequence_visual_layer(sequence.id, %{
          asset_id: image.id,
          kind: "backdrop",
          label: "Throne room",
          fit: "cover"
        })

      {:ok, _track} =
        Editor.upsert_sequence_track(sequence.id, "music", %{
          asset_id: audio.id,
          volume: Decimal.new("0.650")
        })

      drain_analytics()

      assert {:ok, duplicate} = Editor.duplicate_editor_node(scope, flow, sequence)

      assert duplicate.type == "sequence"
      assert duplicate.parent_id == parent.id
      assert duplicate.composition_source_id == composition_source.id
      assert duplicate.position_x == 60.0
      assert duplicate.position_y == 70.0
      assert duplicate.sequence_config.name == "Throne room"
      assert duplicate.sequence_config.width == 640.0
      assert duplicate.sequence_config.height == 360.0
      assert visual_state(duplicate.id) == visual_state(sequence.id)
      assert track_state(duplicate.id) == track_state(sequence.id)

      assert_event_once("flow node created", %{
        "creation_method" => "duplicate",
        "flow_id" => flow.id,
        "has_parent" => true,
        "node_type" => "sequence",
        "project_id" => flow.project_id
      })
    end

    test "rolls back the duplicate and emits no fact when a local asset is outside the project",
         %{
           flow: flow,
           project: project,
           scope: scope,
           user: user
         } do
      dialogue = node_fixture(flow, %{data: %{"text" => "Corrupt source"}})
      image = image_asset_fixture(project, user)

      {:ok, layer} =
        Editor.create_sequence_visual_layer(dialogue.id, %{
          asset_id: image.id,
          kind: "character"
        })

      foreign_project = project_fixture(user)
      foreign_image = image_asset_fixture(foreign_project, user)

      Repo.update_all(
        from(item in SequenceVisualLayer, where: item.id == ^layer.id),
        set: [asset_id: foreign_image.id]
      )

      count_before =
        Repo.aggregate(
          from(node in FlowNode, where: node.flow_id == ^flow.id and is_nil(node.deleted_at)),
          :count
        )

      drain_analytics()

      assert {:error, _reason} = Editor.duplicate_editor_node(scope, flow, dialogue)

      assert Repo.aggregate(
               from(node in FlowNode,
                 where: node.flow_id == ^flow.id and is_nil(node.deleted_at)
               ),
               :count
             ) == count_before

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

      assert {:ok, dialogue_layer} =
               Editor.create_editor_sequence_visual_layer(
                 scope,
                 flow,
                 dialogue.id,
                 %{kind: "backdrop", asset_id: image.id}
               )

      assert_event_once("sequence visual layer created", %{
        "flow_id" => flow.id,
        "has_asset" => true,
        "layer_kind" => "backdrop",
        "project_id" => flow.project_id,
        "sequence_id" => dialogue.id,
        "slot" => "full"
      })

      assert {:ok, _deleted} = Editor.delete_sequence_visual_layer(dialogue_layer)

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

  defp visual_state(owner_id) do
    owner_id
    |> Editor.list_sequence_visual_layers()
    |> Enum.map(fn layer ->
      layer
      |> Map.from_struct()
      |> Map.take([
        :asset_id,
        :layer_key,
        :overridden_fields,
        :removed,
        :kind,
        :label,
        :z_index,
        :slot,
        :x,
        :y,
        :width,
        :height,
        :anchor_x,
        :anchor_y,
        :fit,
        :opacity,
        :visible
      ])
    end)
    |> Enum.sort_by(& &1.layer_key)
  end

  defp track_state(owner_id) do
    owner_id
    |> Editor.list_sequence_tracks()
    |> Enum.map(fn track ->
      track
      |> Map.from_struct()
      |> Map.take([
        :track_key,
        :is_override,
        :overridden_fields,
        :removed,
        :kind,
        :position,
        :asset_id,
        :start_time,
        :end_time,
        :volume
      ])
    end)
    |> Enum.sort_by(& &1.track_key)
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
