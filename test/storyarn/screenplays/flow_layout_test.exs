defmodule Storyarn.Screenplays.FlowLayoutTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.FlowLayout

  @x_center 400.0
  @x_gap 350.0
  @y_start 100.0
  @y_spacing 150.0

  defp make_node(id), do: %{id: id}

  defp make_attrs(type), do: %{type: type, data: %{}, element_ids: [], source: "screenplay_sync"}

  defp make_tree(node_attrs_list, branches \\ []) do
    %{screenplay_id: 1, node_attrs_list: node_attrs_list, branches: branches}
  end

  defp make_branch(source_node_index, choice_id, child_tree) do
    %{source_node_index: source_node_index, choice_id: choice_id, child: child_tree}
  end

  describe "compute_positions/2" do
    test "single page produces vertical stack (backwards compatible)" do
      tree = make_tree([make_attrs("entry"), make_attrs("dialogue"), make_attrs("exit")])
      nodes = [make_node(1), make_node(2), make_node(3)]

      positions = FlowLayout.compute_positions(tree, nodes)

      assert positions[1] == {@x_center, @y_start}
      assert positions[2] == {@x_center, @y_start + @y_spacing}
      assert positions[3] == {@x_center, @y_start + 2 * @y_spacing}
    end

    test "two branches split horizontally below dialogue node" do
      child_a = make_tree([make_attrs("scene")])
      child_b = make_tree([make_attrs("scene")])

      tree =
        make_tree(
          [make_attrs("entry"), make_attrs("dialogue")],
          [
            make_branch(1, "c1", child_a),
            make_branch(1, "c2", child_b)
          ]
        )

      # Flat order: entry(1), dialogue(2), scene_a(3), scene_b(4)
      nodes = [make_node(1), make_node(2), make_node(3), make_node(4)]

      positions = FlowLayout.compute_positions(tree, nodes)

      # Root nodes at center
      assert positions[1] == {@x_center, @y_start}
      assert positions[2] == {@x_center, @y_start + @y_spacing}

      # Branches split horizontally: width=0+0+350=350, start_x=400-175=225
      {x_a, y_a} = positions[3]
      {x_b, y_b} = positions[4]

      assert y_a == y_b
      assert y_a == @y_start + 2 * @y_spacing
      assert x_a < @x_center
      assert x_b > @x_center
      assert_in_delta x_b - x_a, @x_gap, 0.01
    end

    test "asymmetric branches: wider subtree gets more horizontal space" do
      # Branch A has 2 sub-branches (width = 350)
      grandchild_1 = make_tree([make_attrs("scene")])
      grandchild_2 = make_tree([make_attrs("scene")])

      child_a =
        make_tree(
          [make_attrs("scene"), make_attrs("dialogue")],
          [
            make_branch(1, "gc1", grandchild_1),
            make_branch(1, "gc2", grandchild_2)
          ]
        )

      # Branch B is a leaf (width = 0)
      child_b = make_tree([make_attrs("scene")])

      tree =
        make_tree(
          [make_attrs("entry"), make_attrs("dialogue")],
          [
            make_branch(1, "c1", child_a),
            make_branch(1, "c2", child_b)
          ]
        )

      # Flat order: entry(1), dialogue(2), scene_a(3), dialogue_a(4), gc1(5), gc2(6), scene_b(7)
      nodes = Enum.map(1..7, &make_node/1)

      positions = FlowLayout.compute_positions(tree, nodes)

      # Branch A is wider (350) than branch B (0)
      {x_a, _} = positions[3]
      {x_b, _} = positions[7]

      # Branch A center should be left of center, Branch B right of center
      assert x_a < x_b
      # The gap between branch A center and branch B center should be > X_GAP
      # because branch A has width 350 (center at 350/2=175 from its left edge)
      assert x_b - x_a > @x_gap
    end

    test "nested branches produce recursive layout at increasing depth" do
      grandchild = make_tree([make_attrs("scene"), make_attrs("dialogue")])

      child =
        make_tree(
          [make_attrs("scene"), make_attrs("dialogue")],
          [make_branch(1, "c2", grandchild)]
        )

      tree =
        make_tree(
          [make_attrs("entry"), make_attrs("dialogue")],
          [make_branch(1, "c1", child)]
        )

      # Flat: entry(1), dialogue(2), scene_child(3), dialogue_child(4), scene_gc(5), dialogue_gc(6)
      nodes = Enum.map(1..6, &make_node/1)

      positions = FlowLayout.compute_positions(tree, nodes)

      # All 6 nodes should have positions
      assert map_size(positions) == 6

      # Root nodes at center
      assert positions[1] == {@x_center, @y_start}

      # Each level goes deeper in y
      {_, y_root} = positions[1]
      {_, y_child} = positions[3]
      {_, y_gc} = positions[5]

      assert y_child > y_root
      assert y_gc > y_child
    end

    test "branches on different nodes are positioned correctly" do
      child_a = make_tree([make_attrs("scene")])
      child_b = make_tree([make_attrs("scene")])

      # Branching at node 1 AND node 3 (both are dialogue)
      tree =
        make_tree(
          [
            make_attrs("entry"),
            make_attrs("dialogue"),
            make_attrs("scene"),
            make_attrs("dialogue")
          ],
          [
            make_branch(1, "c1", child_a),
            make_branch(3, "c2", child_b)
          ]
        )

      # Flat: entry(1), dialogue(2), scene(3), dialogue2(4), child_a(5), child_b(6)
      nodes = Enum.map(1..6, &make_node/1)

      positions = FlowLayout.compute_positions(tree, nodes)

      assert map_size(positions) == 6

      # Branch A appears after node 1 (dialogue)
      {_, y_branch_a} = positions[5]
      {_, y_dialogue1} = positions[2]
      assert y_branch_a > y_dialogue1

      # Branch B appears after node 3 (dialogue2)
      {_, y_branch_b} = positions[6]
      {_, y_dialogue2} = positions[4]
      assert y_branch_b > y_dialogue2

      # Branch B is lower than branch A
      assert y_branch_b > y_branch_a
    end

    test "parent nodes resume after tallest branch" do
      # Branch A has 3 nodes (tall), Branch B has 1 node (short)
      child_a = make_tree([make_attrs("scene"), make_attrs("dialogue"), make_attrs("exit")])
      child_b = make_tree([make_attrs("scene")])

      tree =
        make_tree(
          [make_attrs("entry"), make_attrs("dialogue"), make_attrs("exit")],
          [
            make_branch(1, "c1", child_a),
            make_branch(1, "c2", child_b)
          ]
        )

      # Flat: entry(1), dialogue(2), exit(3), scene_a(4), dialogue_a(5), exit_a(6), scene_b(7)
      nodes = Enum.map(1..7, &make_node/1)

      positions = FlowLayout.compute_positions(tree, nodes)

      # The exit node (3) should be below the tallest branch
      {_, y_exit} = positions[3]
      {_, y_tallest_end} = positions[6]

      # Exit should be at or after the tallest branch's last node
      assert y_exit >= y_tallest_end
    end
  end
end
