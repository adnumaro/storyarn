defmodule Storyarn.Screenplays.ScreenplayElementTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.ScreenplayElement

  describe "Hub marker color normalization" do
    test "normalizes legacy colors when creating imported markers" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "hub_marker",
          data: %{"hub_node_id" => "checkpoint", "color" => "blue"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#3b82f6"
    end

    test "normalizes existing legacy colors on update" do
      element = %ScreenplayElement{
        type: "hub_marker",
        data: %{"hub_node_id" => "checkpoint", "color" => "amber"}
      }

      changeset = ScreenplayElement.update_changeset(element, %{content: "Checkpoint"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#f59e0b"
    end

    test "does not add a Hub color to other element types" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "action",
          data: %{}
        })

      assert changeset.valid?
      refute Map.has_key?(Ecto.Changeset.get_field(changeset, :data), "color")
    end
  end
end
