defmodule Storyarn.Flows.FlowNodeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.FlowNode

  describe "create_changeset/2 source field" do
    test "defaults source to manual" do
      changeset = FlowNode.create_changeset(%FlowNode{}, %{type: "dialogue"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :source) == "manual"
      assert %{"localization_id" => "dialogue_" <> _uuid} = Ecto.Changeset.get_field(changeset, :data)
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

  describe "runtime localization identifiers" do
    test "generates stable identifiers for new responses that do not have one" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{
          type: "dialogue",
          data: %{"responses" => [%{"text" => "Yes"}, %{"text" => "No"}]}
        })

      assert changeset.valid?

      assert %{"responses" => [%{"id" => first_id}, %{"id" => second_id}]} =
               Ecto.Changeset.get_field(changeset, :data)

      assert first_id != second_id
      assert String.starts_with?(first_id, "response_")
      assert String.starts_with?(second_id, "response_")
    end

    test "rejects malformed explicit identifiers instead of replacing them" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{
          type: "dialogue",
          data: %{
            "localization_id" => "bad id",
            "responses" => [%{"id" => "bad.id", "text" => "No"}]
          }
        })

      refute changeset.valid?
      assert Enum.any?(changeset.errors, &match?({:data, {"must contain a valid localization_id", _}}, &1))
      assert Enum.any?(changeset.errors, &match?({:data, {"every response must contain a valid id", _}}, &1))
    end

    test "normalizes atom-keyed response data before validating its shape" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{
          type: "dialogue",
          data: %{responses: "not-a-list"}
        })

      refute changeset.valid?
      assert Enum.any?(changeset.errors, &match?({:data, {"responses must be a list", _}}, &1))
    end
  end

  describe "Hub color normalization" do
    test "materializes legacy named colors as their original hex values" do
      changeset =
        FlowNode.materialize_changeset(%FlowNode{}, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "blue"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#3b82f6"
    end
  end
end
