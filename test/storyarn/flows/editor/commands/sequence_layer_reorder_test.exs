defmodule Storyarn.Flows.SequenceLayerReorderTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Editor.Commands.CompositionOwnerDuplicate
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    source = node_fixture(flow)
    owner = node_fixture(flow)
    {:ok, owner} = Flows.set_composition_source(owner.id, source.id)
    image = image_asset_fixture(project, user)
    {:ok, inherited} = Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "character"})
    {:ok, local} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "overlay"})
    %{flow: flow, owner: owner, source: source, inherited: inherited, local: local, image: image}
  end

  test "a complete global reorder is one reversible edit with no ancestor or layer-row mutation", context do
    %{owner: owner, source: source, inherited: inherited, local: local} = context
    source_before = Repo.get!(FlowNode, source.id)
    layers_before = Repo.all(SequenceVisualLayer)

    assert {:ok, history} =
             Flows.transact_sequence_composition(owner.id, fn ->
               Flows.reorder_sequence_visual_layers(owner.id, [local.layer_key, inherited.layer_key])
             end)

    assert keys(context.flow.id, owner.id) == [local.layer_key, inherited.layer_key]
    assert Repo.get!(FlowNode, source.id) == source_before
    assert Repo.all(SequenceVisualLayer) == layers_before
    assert history.previous["composition_layer_order"] == nil
    assert history.current["composition_layer_order"] == [local.layer_key, inherited.layer_key]

    assert {:ok, _} = Flows.restore_sequence_composition(owner.id, history.previous, history.current)
    assert keys(context.flow.id, owner.id) == [inherited.layer_key, local.layer_key]
    assert {:ok, _} = Flows.restore_sequence_composition(owner.id, history.current, history.previous)
    assert keys(context.flow.id, owner.id) == [local.layer_key, inherited.layer_key]
  end

  test "stale, duplicate and incomplete layer lists fail without a partial change", context do
    %{owner: owner, source: source, inherited: inherited, local: local, image: image} = context
    expected = [inherited.layer_key, local.layer_key]
    {:ok, _} = Flows.update_sequence_visual_layer(local, %{visible: false})

    for invalid <- [[inherited.layer_key], expected ++ ["foreign-key"], []] do
      assert {:error, :sequence_layer_order_conflict} = Flows.reorder_sequence_visual_layers(owner.id, invalid)
    end

    assert {:error, :invalid_sequence_layer_order} =
             Flows.reorder_sequence_visual_layers(owner.id, [local.layer_key, local.layer_key])

    assert {:ok, _} = Flows.reorder_sequence_visual_layers(owner.id, Enum.reverse(expected))
    {:ok, before} = Flows.capture_sequence_composition(owner.id)
    {:ok, _new} = Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "prop"})
    assert {:error, :sequence_layer_order_conflict} = Flows.reorder_sequence_visual_layers(owner.id, expected)
    assert {:ok, ^before} = Flows.capture_sequence_composition(owner.id)
  end

  test "geometry outside the frame survives persistence and undo, while anchors stay normalized", context do
    %{owner: owner, local: local} = context
    {:ok, initial} = Flows.capture_sequence_composition(owner.id)
    assert {:ok, layer} = Flows.update_sequence_visual_layer(local, %{x: -1.5, y: 2.2, width: 3.0, height: 4.0})
    assert Repo.get!(SequenceVisualLayer, layer.id).x == -1.5
    {:ok, offstage} = Flows.capture_sequence_composition(owner.id)
    assert {:ok, _} = Flows.restore_sequence_composition(owner.id, initial)
    assert {:ok, ^offstage} = Flows.restore_sequence_composition(owner.id, offstage)

    invalid = put_in(offstage, ["visual_layers", Access.at(0), "anchor_x"], -0.2)
    assert {:error, :invalid_composition_snapshot} = Flows.restore_sequence_composition(owner.id, invalid)
  end

  test "legacy history snapshots omit order and regular node edits cannot overwrite it", context do
    %{flow: flow, owner: owner, inherited: inherited, local: local} = context
    {:ok, initial} = Flows.capture_sequence_composition(owner.id)
    order = [local.layer_key, inherited.layer_key]
    {:ok, _} = Flows.reorder_sequence_visual_layers(owner.id, order)

    for {operation, payload} <- [
          {:merge_form, %{params: %{"text" => "New line", "composition_layer_order" => []}}},
          {:restore_data, %{data: %{"text" => "Restored line", "composition_layer_order" => []}}}
        ] do
      assert {:ok, %{node: updated}} = Flows.edit_node(flow.id, owner.id, operation, payload)
      assert updated.data["composition_layer_order"] == order
    end

    assert {:error, :field_not_editable} =
             Flows.edit_node(flow.id, owner.id, :put_field, %{field: "composition_layer_order", value: []})

    assert {:ok, restored} =
             Flows.restore_sequence_composition(owner.id, Map.delete(initial, "composition_layer_order"))

    assert restored["composition_layer_order"] == nil
    assert Flows.get_node(flow.id, owner.id).data["text"] == "Restored line"
  end

  test "duplication preserves logical order and layer identities for dialogue and sequence owners", context do
    %{flow: flow, owner: owner, inherited: inherited, local: local, image: image} = context
    order = [local.layer_key, inherited.layer_key]
    {:ok, owner} = Flows.reorder_sequence_visual_layers(owner.id, order)
    assert {:ok, duplicate} = CompositionOwnerDuplicate.duplicate(flow, owner)
    assert keys(flow.id, duplicate.id) == order

    {:ok, group} = Flows.create_sequence(flow.id, %{"name" => "Group"})
    {:ok, a} = Flows.create_sequence_visual_layer(group.id, %{asset_id: image.id, kind: "backdrop"})
    {:ok, b} = Flows.create_sequence_visual_layer(group.id, %{asset_id: image.id, kind: "character"})
    group_order = [b.layer_key, a.layer_key]
    {:ok, group} = Flows.reorder_sequence_visual_layers(group.id, group_order)
    assert {:ok, group_duplicate} = CompositionOwnerDuplicate.duplicate(flow, group)
    assert keys(flow.id, group_duplicate.id) == group_order
  end

  defp keys(flow_id, owner_id) do
    graph = Flows.load_runtime_graph(flow_id)
    owner_id |> Flows.compose_node_sequences(graph.nodes) |> Map.fetch!(:visual_layers) |> Enum.map(& &1.layer_key)
  end
end
