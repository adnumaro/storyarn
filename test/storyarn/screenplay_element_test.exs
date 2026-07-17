defmodule Storyarn.Screenplays.ScreenplayElementTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.ScreenplayElement

  describe "Hub marker color normalization" do
    test "defaults legacy colors in current create changesets" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "hub_marker",
          data: %{"hub_node_id" => "checkpoint", "color" => "blue"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#be185d"
    end

    test "defaults existing legacy colors in current update changesets" do
      element = %ScreenplayElement{
        type: "hub_marker",
        data: %{"hub_node_id" => "checkpoint", "color" => "amber"}
      }

      changeset = ScreenplayElement.update_changeset(element, %{content: "Checkpoint"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#be185d"
    end

    test "defaults nil data in create and update changesets" do
      create_changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "hub_marker",
          data: nil
        })

      update_changeset =
        ScreenplayElement.update_changeset(
          %ScreenplayElement{type: "hub_marker", data: nil},
          %{content: "Checkpoint"}
        )

      for changeset <- [create_changeset, update_changeset] do
        assert changeset.valid?
        assert Ecto.Changeset.get_field(changeset, :data) == %{"color" => "#be185d"}
      end
    end

    test "preserves valid hex colors" do
      changeset =
        ScreenplayElement.create_changeset(%ScreenplayElement{}, %{
          type: "hub_marker",
          data: %{"hub_node_id" => "checkpoint", "color" => "#3b82f6"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#3b82f6"
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
