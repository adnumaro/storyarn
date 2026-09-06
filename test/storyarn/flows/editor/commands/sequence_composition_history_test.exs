defmodule Storyarn.Flows.SequenceCompositionHistoryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.SequenceCompositionHistory

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  test "capture and restore round-trip source, sequence config, position, and layers", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, source} = Flows.create_sequence(flow.id, %{"name" => "Source"})

    {:ok, owner} =
      Flows.create_sequence(flow.id, %{
        "name" => "Shot",
        "position_x" => 12.5,
        "position_y" => -8.0,
        "width" => 720.0,
        "height" => 405.0
      })

    {:ok, owner} = Flows.set_composition_source(owner.id, source.id)
    image = image_asset_fixture(project, user)
    audio = audio_asset_fixture(project, user)

    {:ok, layer} =
      Flows.create_sequence_visual_layer(owner.id, %{
        "asset_id" => image.id,
        "kind" => "character",
        "label" => "Hero",
        "slot" => "bottom-left",
        "x" => 0.23,
        "y" => 0.91,
        "width" => 0.31,
        "height" => 0.82,
        "opacity" => 0.75,
        "visible" => false
      })

    {:ok, track} =
      Flows.upsert_sequence_track(owner.id, "ambience", %{
        "asset_id" => audio.id,
        "volume" => Decimal.new("0.4")
      })

    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)
    assert captured["owner_id"] == owner.id
    assert captured["flow_id"] == flow.id
    assert captured["composition_source_id"] == source.id
    assert captured["config"] == %{"name" => "Shot", "width" => 720.0, "height" => 405.0}
    assert [%{"layer_key" => layer_key}] = captured["visual_layers"]
    assert layer_key == layer.layer_key
    refute Map.has_key?(captured, "tracks")

    {:ok, _owner} = Flows.set_composition_source(owner.id, nil)

    {:ok, _owner} =
      Flows.update_sequence(owner, %{
        "name" => "Changed",
        "position_x" => 900.0,
        "position_y" => 600.0,
        "width" => 300.0,
        "height" => 200.0
      })

    {:ok, _layer} =
      Flows.update_sequence_visual_layer(layer, %{"opacity" => 0.1, "visible" => true})

    {:ok, _track} =
      Flows.upsert_sequence_track(owner.id, "ambience", %{"volume" => Decimal.new("0.2")})

    assert {:ok, restored} = Flows.restore_sequence_composition(owner.id, captured)
    assert restored == captured
    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
    assert [preserved_track] = Flows.list_sequence_tracks(owner.id)
    assert preserved_track.id == track.id
    assert Decimal.equal?(preserved_track.volume, Decimal.new("0.2"))
  end

  test "round-trip preserves inherited patches and tombstones", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
    dialogue = node_fixture(flow, %{parent_id: base.id, data: %{"text" => "Line"}})
    first_image = image_asset_fixture(project, user)
    second_image = image_asset_fixture(project, user)

    {:ok, inherited_layer} =
      Flows.create_sequence_visual_layer(base.id, %{
        "asset_id" => first_image.id,
        "kind" => "character"
      })

    {:ok, removed_layer} =
      Flows.create_sequence_visual_layer(base.id, %{
        "asset_id" => second_image.id,
        "kind" => "prop"
      })

    {:ok, _patch} =
      Flows.override_sequence_visual_layer(dialogue.id, inherited_layer.layer_key, %{
        "opacity" => 0.35
      })

    {:ok, _tombstone} = Flows.remove_sequence_visual_layer(dialogue.id, removed_layer.layer_key)

    assert {:ok, captured} = Flows.capture_sequence_composition(dialogue.id)

    assert {:ok, :inherited} =
             Flows.revert_sequence_visual_layer_fields(
               dialogue.id,
               inherited_layer.layer_key,
               ["opacity"]
             )

    assert {:ok, :inherited} =
             Flows.restore_sequence_visual_layer(dialogue.id, removed_layer.layer_key)

    {:ok, _dialogue} = Flows.set_composition_source(dialogue.id, nil)

    assert {:ok, ^captured} = Flows.restore_sequence_composition(dialogue.id, captured)
    assert {:ok, ^captured} = Flows.capture_sequence_composition(dialogue.id)
  end

  test "transact captures both states under one owner lock and rolls back callback errors", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    image = image_asset_fixture(project, user)
    assert {:ok, before} = SequenceCompositionHistory.capture(owner.id)

    assert {:ok,
            %{
              result: result,
              previous: ^before,
              current: after_create
            }} =
             SequenceCompositionHistory.transact(owner.id, fn ->
               Flows.create_sequence_visual_layer(owner.id, %{
                 "asset_id" => image.id,
                 "kind" => "character"
               })
             end)

    assert result.asset_id == image.id
    assert [%{"asset_id" => image_id}] = after_create["visual_layers"]
    assert image_id == image.id
    assert {:ok, ^after_create} = SequenceCompositionHistory.capture(owner.id)

    assert {:ok, ^before} =
             SequenceCompositionHistory.restore(owner.id, before, after_create)

    assert {:error, :composition_history_conflict} =
             SequenceCompositionHistory.restore(owner.id, before, after_create)

    assert {:ok, ^before} = SequenceCompositionHistory.capture(owner.id)

    assert {:ok, ^after_create} =
             SequenceCompositionHistory.restore(owner.id, after_create, before)

    assert {:error, :cancelled} =
             SequenceCompositionHistory.transact(owner.id, fn ->
               with {:ok, layer} <-
                      Flows.create_sequence_visual_layer(owner.id, %{
                        "asset_id" => image.id,
                        "kind" => "prop"
                      }),
                    {:ok, _layer} <- Flows.update_sequence_visual_layer(layer, %{"opacity" => 0.1}) do
                 {:error, :cancelled}
               end
             end)

    assert {:ok, ^after_create} = SequenceCompositionHistory.capture(owner.id)
  end

  test "restore rejects a snapshot bound to another owner or flow", %{user: user, flow: flow} do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)

    foreign_project = project_fixture(user)
    foreign_flow = flow_fixture(foreign_project)
    foreign_owner = node_fixture(foreign_flow)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(
               owner.id,
               Map.put(captured, "owner_id", foreign_owner.id)
             )

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(
               owner.id,
               Map.put(captured, "flow_id", foreign_flow.id)
             )

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, Map.delete(captured, "owner_id"))

    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
  end

  test "restore rejects foreign sources and assets without partially changing the owner", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    image = image_asset_fixture(project, user)

    {:ok, _layer} =
      Flows.create_sequence_visual_layer(owner.id, %{
        "asset_id" => image.id,
        "kind" => "backdrop"
      })

    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)

    foreign_project = project_fixture(user)
    foreign_flow = flow_fixture(foreign_project)
    foreign_source = node_fixture(foreign_flow)
    foreign_image = image_asset_fixture(foreign_project, user)

    assert {:error, :invalid_composition_snapshot} =
             captured
             |> Map.put("composition_source_id", foreign_source.id)
             |> then(&Flows.restore_sequence_composition(owner.id, &1))

    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)

    foreign_visual =
      update_in(captured, ["visual_layers", Access.at(0), "asset_id"], fn _current ->
        foreign_image.id
      end)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, foreign_visual)

    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
  end

  test "restore rejects malformed row identities before replacing local state", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    image = image_asset_fixture(project, user)

    {:ok, _layer} =
      Flows.create_sequence_visual_layer(owner.id, %{
        "asset_id" => image.id,
        "kind" => "character"
      })

    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)

    [layer] = captured["visual_layers"]
    duplicate_local_layers = Map.put(captured, "visual_layers", [layer, layer])

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, duplicate_local_layers)

    oversized_key =
      update_in(captured, ["visual_layers", Access.at(0), "layer_key"], fn _current ->
        String.duplicate("x", 65)
      end)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, oversized_key)

    invalid_asset_id =
      update_in(captured, ["visual_layers", Access.at(0), "asset_id"], fn _current -> "not-an-id" end)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, invalid_asset_id)

    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
  end

  test "restore rejects orphan patches and malformed local definitions", %{
    user: user,
    project: project,
    flow: flow
  } do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    image = image_asset_fixture(project, user)

    {:ok, _layer} =
      Flows.create_sequence_visual_layer(owner.id, %{
        "asset_id" => image.id,
        "kind" => "character"
      })

    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)

    invalid_snapshots = [
      update_in(captured, ["visual_layers", Access.at(0), "overridden_fields"], fn _fields ->
        ["opacity"]
      end),
      update_in(captured, ["visual_layers", Access.at(0), "removed"], fn _removed -> true end)
    ]

    for invalid_snapshot <- invalid_snapshots do
      assert {:error, :invalid_composition_snapshot} =
               Flows.restore_sequence_composition(owner.id, invalid_snapshot, captured)

      assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
    end
  end

  test "restore rolls back when removing a base would orphan a descendant patch", %{
    project: project,
    user: user,
    flow: flow
  } do
    {:ok, root} = Flows.create_sequence(flow.id, %{"name" => "Root"})
    child = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Child", "responses" => []}})
    {:ok, _child} = Flows.set_composition_source(child.id, root.id)
    image = image_asset_fixture(project, user)

    assert {:ok, without_layer} = Flows.capture_sequence_composition(root.id)

    {:ok, layer} =
      Flows.create_sequence_visual_layer(root.id, %{
        "asset_id" => image.id,
        "kind" => "character"
      })

    assert {:ok, with_layer} = Flows.capture_sequence_composition(root.id)

    {:ok, _patch} =
      Flows.override_sequence_visual_layer(child.id, layer.layer_key, %{
        "opacity" => 0.25
      })

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(root.id, without_layer, with_layer)

    assert {:ok, ^with_layer} = Flows.capture_sequence_composition(root.id)
    assert %{layer_key: layer_key} = Flows.get_sequence_visual_layer_by_key(child.id, layer.layer_key)
    assert layer_key == layer.layer_key
  end

  test "restore also protects patches owned by deleted descendants", %{
    project: project,
    user: user,
    flow: flow
  } do
    {:ok, root} = Flows.create_sequence(flow.id, %{"name" => "Root"})
    child = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Child", "responses" => []}})
    {:ok, _child} = Flows.set_composition_source(child.id, root.id)
    image = image_asset_fixture(project, user)
    assert {:ok, without_layer} = Flows.capture_sequence_composition(root.id)

    {:ok, layer} =
      Flows.create_sequence_visual_layer(root.id, %{
        "asset_id" => image.id,
        "kind" => "character"
      })

    assert {:ok, with_layer} = Flows.capture_sequence_composition(root.id)

    {:ok, _patch} =
      Flows.override_sequence_visual_layer(child.id, layer.layer_key, %{
        "opacity" => 0.25
      })

    assert {:ok, _deleted_child, _meta} = Flows.delete_node(child)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(root.id, without_layer, with_layer)

    assert {:ok, ^with_layer} = Flows.capture_sequence_composition(root.id)
    assert %{layer_key: layer_key} = Flows.get_sequence_visual_layer_by_key(child.id, layer.layer_key)
    assert layer_key == layer.layer_key
  end

  test "restore rejects a deleted composition source before writing the owner", %{flow: flow} do
    {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Owner"})
    {:ok, source} = Flows.create_sequence(flow.id, %{"name" => "Deleted source"})
    assert {:ok, captured} = Flows.capture_sequence_composition(owner.id)
    assert {:ok, _deleted_source, _meta} = Flows.delete_node(source)
    invalid = Map.put(captured, "composition_source_id", source.id)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(owner.id, invalid, captured)

    assert {:ok, ^captured} = Flows.capture_sequence_composition(owner.id)
  end

  test "restore rejects deleted sources inside an affected descendant chain", %{flow: flow} do
    {:ok, root} = Flows.create_sequence(flow.id, %{"name" => "Root"})
    child = node_fixture(flow, %{type: "dialogue"})
    grandchild = node_fixture(flow, %{type: "dialogue"})
    {:ok, _child} = Flows.set_composition_source(child.id, root.id)
    {:ok, _grandchild} = Flows.set_composition_source(grandchild.id, child.id)
    {:ok, _deleted_grandchild, _meta} = Flows.delete_node(grandchild)
    {:ok, _deleted_child, _meta} = Flows.delete_node(child)
    assert {:ok, captured} = Flows.capture_sequence_composition(root.id)

    assert {:error, :invalid_composition_snapshot} =
             Flows.restore_sequence_composition(root.id, captured)

    assert {:ok, ^captured} = Flows.capture_sequence_composition(root.id)
  end

  test "restore accepts complete descendant definitions that reopen inherited tombstones", %{
    project: project,
    user: user,
    flow: flow
  } do
    {:ok, root} = Flows.create_sequence(flow.id, %{"name" => "Root"})
    middle = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Middle", "responses" => []}})
    leaf = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Leaf", "responses" => []}})
    {:ok, _middle} = Flows.set_composition_source(middle.id, root.id)
    {:ok, _leaf} = Flows.set_composition_source(leaf.id, middle.id)
    image = image_asset_fixture(project, user)

    {:ok, layer} =
      Flows.create_sequence_visual_layer(root.id, %{
        "asset_id" => image.id,
        "kind" => "character"
      })

    {:ok, _layer_tombstone} = Flows.remove_sequence_visual_layer(middle.id, layer.layer_key)
    {:ok, reopened_layer} = Flows.restore_sequence_visual_layer(leaf.id, layer.layer_key)

    assert MapSet.new(reopened_layer.overridden_fields) ==
             MapSet.new(~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible))

    assert {:ok, captured} = Flows.capture_sequence_composition(leaf.id)
    assert {:ok, ^captured} = Flows.restore_sequence_composition(leaf.id, captured)
  end
end
