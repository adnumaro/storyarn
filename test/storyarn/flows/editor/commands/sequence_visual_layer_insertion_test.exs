defmodule Storyarn.Flows.SequenceVisualLayerInsertionTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    owner = node_fixture(flow, %{type: "dialogue"})
    image = image_asset_fixture(project, user)
    %{flow: flow, owner: owner, image: image}
  end

  test "exhausting PostgreSQL z-index range returns a changeset error without changing the stack", context do
    %{flow: flow, owner: owner, image: image} = context

    {:ok, highest} =
      Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "backdrop", z_index: 2_147_483_647})

    {:ok, before} = Flows.capture_sequence_composition(owner.id)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "character"})

    assert Keyword.has_key?(changeset.errors, :z_index)
    assert keys(flow.id, owner.id) == [highest.layer_key]
    assert {:ok, ^before} = Flows.capture_sequence_composition(owner.id)
  end

  test "new images stay above an existing backdrop regardless of their default kind order", context do
    %{flow: flow, owner: owner, image: image} = context
    {:ok, backdrop} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "backdrop", z_index: 900})

    {:ok, character} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "character"})
    {:ok, next_backdrop} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "backdrop"})
    {:ok, prop} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "prop"})

    assert keys(flow.id, owner.id) == [backdrop.layer_key, character.layer_key, next_backdrop.layer_key, prop.layer_key]
    assert Flows.get_sequence_visual_layer(owner.id, backdrop.id).z_index == 900
    assert is_nil(Flows.get_node!(flow.id, owner.id).data["composition_layer_order"])
  end

  test "new images stay above inherited manual order and previously unlisted local keys", context do
    %{flow: flow, owner: owner, image: image} = context
    source = node_fixture(flow, %{type: "dialogue"})
    {:ok, _owner} = Flows.set_composition_source(owner.id, source.id)
    {:ok, backdrop} = Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "backdrop", z_index: 900})

    {:ok, character} =
      Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "character", z_index: 10})

    order = [backdrop.layer_key, character.layer_key]
    {:ok, _source} = Flows.reorder_sequence_visual_layers(source.id, order)
    {:ok, local} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "overlay", z_index: 800})
    {:ok, source_before} = Flows.capture_sequence_composition(source.id)

    {:ok, image_layer} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "backdrop"})

    assert keys(flow.id, owner.id) == order ++ [local.layer_key, image_layer.layer_key]
    assert {:ok, ^source_before} = Flows.capture_sequence_composition(source.id)
    assert is_nil(Flows.get_node!(flow.id, owner.id).data["composition_layer_order"])

    # Source reorders still propagate; inserting an image does not freeze continuity.
    {:ok, _source} = Flows.reorder_sequence_visual_layers(source.id, Enum.reverse(order))
    assert keys(flow.id, owner.id) == Enum.reverse(order, [local.layer_key, image_layer.layer_key])
  end

  test "creation above a local manual order is one reversible edit without reordering existing layers", context do
    %{flow: flow, owner: owner, image: image} = context
    source = node_fixture(flow, %{type: "dialogue"})
    {:ok, _owner} = Flows.set_composition_source(owner.id, source.id)
    {:ok, inherited} = Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "backdrop"})
    {:ok, local} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "character"})
    order = [local.layer_key, inherited.layer_key]
    {:ok, _owner} = Flows.reorder_sequence_visual_layers(owner.id, order)
    {:ok, first} = Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "overlay"})
    {:ok, source_before} = Flows.capture_sequence_composition(source.id)

    assert {:ok, history} =
             Flows.transact_sequence_composition(owner.id, fn ->
               Flows.create_sequence_visual_layer(owner.id, %{asset_id: image.id, kind: "backdrop"})
             end)

    expected = order ++ [first.layer_key, history.result.layer_key]
    assert keys(flow.id, owner.id) == expected
    assert history.current["composition_layer_order"] == order
    assert {:ok, ^source_before} = Flows.capture_sequence_composition(source.id)

    assert {:ok, _} = Flows.restore_sequence_composition(owner.id, history.previous, history.current)
    assert keys(flow.id, owner.id) == order ++ [first.layer_key]
    assert {:ok, _} = Flows.restore_sequence_composition(owner.id, history.current, history.previous)
    assert keys(flow.id, owner.id) == expected
  end

  defp keys(flow_id, owner_id) do
    graph = Flows.load_runtime_graph(flow_id)
    composition = Flows.compose_node_sequences(owner_id, graph.nodes)
    assert composition.diagnostics == []

    assert Enum.map(composition.visual_layers, & &1.stack_index) ==
             Enum.to_list(0..(length(composition.visual_layers) - 1))

    Enum.map(composition.visual_layers, & &1.layer_key)
  end
end
