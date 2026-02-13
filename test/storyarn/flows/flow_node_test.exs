defmodule Storyarn.Flows.FlowNodeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.FlowNode

  describe "create_changeset/2 source field" do
    test "defaults source to manual" do
      changeset = FlowNode.create_changeset(%FlowNode{}, %{type: "dialogue"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :source) == "manual"
    end

    test "accepts screenplay_sync source" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{type: "dialogue", source: "screenplay_sync"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source) == "screenplay_sync"
    end

    test "rejects invalid source value" do
      changeset = FlowNode.create_changeset(%FlowNode{}, %{type: "dialogue", source: "unknown"})
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:source]
    end
  end
end
