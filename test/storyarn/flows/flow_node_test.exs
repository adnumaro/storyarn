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

    test "updates never invent response ids and preserve the dialogue identity" do
      localization_id = "dialogue_existing"

      node = %FlowNode{
        type: "dialogue",
        data: %{
          "localization_id" => localization_id,
          "responses" => [%{"id" => "response_existing", "text" => "Before"}]
        }
      }

      missing_response_id =
        FlowNode.data_changeset(node, %{
          data: %{
            "responses" => [%{"text" => "After"}]
          }
        })

      refute missing_response_id.valid?
      assert Ecto.Changeset.get_field(missing_response_id, :data)["localization_id"] == localization_id

      assert Enum.any?(
               missing_response_id.errors,
               &match?({:data, {"every response must contain a valid id", _}}, &1)
             )

      changed_localization_id =
        FlowNode.data_changeset(node, %{
          data: %{
            "localization_id" => "dialogue_replacement",
            "responses" => [%{"id" => "response_existing", "text" => "After"}]
          }
        })

      refute changed_localization_id.valid?

      assert Enum.any?(
               changed_localization_id.errors,
               &match?({:data, {"cannot change an existing localization_id", _}}, &1)
             )
    end

    test "snapshot materialization preserves explicit identities and rejects missing ones" do
      attrs = %{
        type: "dialogue",
        data: %{
          "localization_id" => "dialogue_snapshot",
          "responses" => [
            %{"id" => "response_snapshot_one", "text" => "One"},
            %{"id" => "response_snapshot_two", "text" => "Two"}
          ]
        }
      }

      changeset = FlowNode.materialize_changeset(%FlowNode{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data) == attrs.data

      missing_localization_id =
        FlowNode.materialize_changeset(%FlowNode{}, %{
          type: "dialogue",
          data: %{"responses" => attrs.data["responses"]}
        })

      refute missing_localization_id.valid?
      refute Ecto.Changeset.get_field(missing_localization_id, :data)["localization_id"]

      missing_response_id =
        FlowNode.materialize_changeset(%FlowNode{}, %{
          type: "dialogue",
          data: %{
            "localization_id" => "dialogue_snapshot",
            "responses" => [%{"text" => "No identity"}]
          }
        })

      refute missing_response_id.valid?
      refute hd(Ecto.Changeset.get_field(missing_response_id, :data)["responses"])["id"]
    end
  end

  describe "Hub color normalization" do
    test "defaults legacy names in current create changesets" do
      changeset =
        FlowNode.create_changeset(%FlowNode{}, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "blue"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :data)["color"] == "#be185d"
    end

    test "defaults legacy names in current update and data changesets" do
      node = %FlowNode{
        type: "hub",
        data: %{"hub_id" => "checkpoint", "color" => "#3b82f6"}
      }

      update_changeset =
        FlowNode.update_changeset(node, %{
          data: %{"hub_id" => "checkpoint", "color" => "blue"}
        })

      data_changeset =
        FlowNode.data_changeset(node, %{
          data: %{"hub_id" => "checkpoint", "color" => "blue"}
        })

      assert update_changeset.valid?
      assert data_changeset.valid?
      assert Ecto.Changeset.get_field(update_changeset, :data)["color"] == "#be185d"
      assert Ecto.Changeset.get_field(data_changeset, :data)["color"] == "#be185d"
    end

    test "preserves the existing color when update data omits it" do
      node = %FlowNode{
        type: "hub",
        data: %{
          "hub_id" => "checkpoint",
          "label" => "Checkpoint",
          "color" => "#3b82f6"
        }
      }

      update_changeset =
        FlowNode.update_changeset(node, %{
          "data" => %{"label" => "Updated checkpoint"}
        })

      data_changeset =
        FlowNode.data_changeset(node, %{
          data: %{hub_id: "updated-checkpoint"}
        })

      assert update_changeset.valid?
      assert data_changeset.valid?
      assert Ecto.Changeset.get_field(update_changeset, :data)["color"] == "#3b82f6"
      assert Ecto.Changeset.get_field(data_changeset, :data)["color"] == "#3b82f6"
    end

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
