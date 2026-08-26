defmodule Storyarn.Scenes.References.Commands.VariableProjectionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.References.Commands.VariableProjection, as: VariableReferenceTracker

  test "accepts atom- and string-keyed restore sources without references" do
    assert :ok =
             VariableReferenceTracker.validate_snapshot_variable_references(1, [
               %{
                 source_type: "scene_pin",
                 source_id: 10,
                 action_type: nil,
                 action_data: %{},
                 condition: nil
               },
               %{
                 "source_type" => "scene_zone",
                 "source_id" => 11,
                 "action_type" => "action",
                 "action_data" => %{"assignments" => []},
                 "condition" => nil
               },
               %{
                 source_type: "scene_ambient_flow",
                 source_id: 12,
                 trigger_type: "on_enter",
                 trigger_config: %{}
               }
             ])
  end

  test "rejects malformed Scene action collections instead of dropping references" do
    cases = [
      {
        %{
          source_type: "scene_zone",
          source_id: 20,
          action_type: "action",
          action_data: %{"assignments" => ["not-an-assignment-map"]},
          condition: nil
        },
        {:malformed_variable_reference, "scene_zone", 20, :assignment, "not-an-assignment-map"}
      },
      {
        %{
          source_type: "scene_zone",
          source_id: 21,
          action_type: "collection",
          action_data: %{"items" => ["not-an-item-map"]},
          condition: nil
        },
        {:malformed_variable_reference, "scene_zone", 21, {:collection_item, 0}, "not-an-item-map"}
      },
      {
        %{
          source_type: "scene_zone",
          source_id: 22,
          action_type: "collection",
          action_data: %{},
          condition: nil
        },
        {:malformed_variable_reference, "scene_zone", 22, :collection_items, nil}
      },
      {
        %{
          source_type: "scene_zone",
          source_id: 23,
          action_type: "collection",
          action_data: [],
          condition: nil
        },
        {:invalid_variable_reference_source, "scene_zone", 23}
      }
    ]

    for {source, reason} <- cases do
      assert {:error, ^reason} =
               VariableReferenceTracker.validate_snapshot_variable_references(1, [source])
    end
  end
end
