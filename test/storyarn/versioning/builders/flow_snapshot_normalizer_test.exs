defmodule Storyarn.Versioning.Builders.FlowSnapshotNormalizerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer

  test "normalizes legacy runtime ids and every dependent reference" do
    snapshot = %{
      "nodes" => [
        %{
          "original_id" => 10,
          "type" => "dialogue",
          "data" => %{
            "localization_id" => "dialogue.legacy",
            "responses" => [
              %{"id" => "choice.one", "text" => "One"},
              %{"text" => "Two"}
            ]
          }
        },
        %{"original_id" => 11, "type" => "hub", "data" => %{}},
        %{"original_id" => 12, "type" => "hub", "data" => %{}}
      ],
      "connections" => [
        %{"source_node_index" => 0, "target_node_index" => 1, "source_pin" => "choice.one"},
        %{"source_node_index" => 0, "target_node_index" => 2, "source_pin" => "resp_choice.one"}
      ],
      "localization" => [
        %{
          "source_type" => "flow_node",
          "source_id" => 10,
          "source_field" => "response.choice.one.text"
        }
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    [dialogue | _rest] = normalized["nodes"]
    [first_response, second_response] = dialogue["data"]["responses"]

    assert dialogue["data"]["localization_id"] == "dialogue_legacy"
    assert first_response["id"] == "choice_one"
    assert RuntimeKey.valid_response_id?(second_response["id"])
    assert second_response["id"] =~ "response_legacy_"

    assert Enum.map(normalized["connections"], & &1["source_pin"]) == [
             "choice_one",
             "resp_choice_one"
           ]

    assert [%{"source_field" => "response.choice_one.text"}] = normalized["localization"]
  end

  test "keeps valid ids stable and only rekeys later duplicates" do
    snapshot = %{
      "nodes" => [
        %{
          "original_id" => 20,
          "type" => "dialogue",
          "data" => %{
            "localization_id" => "shared_dialogue",
            "responses" => [
              %{"id" => "shared_response", "text" => "First"},
              %{"id" => "shared_response", "text" => "Second"}
            ]
          }
        },
        %{
          "original_id" => 21,
          "type" => "dialogue",
          "data" => %{"localization_id" => "shared_dialogue", "responses" => []}
        },
        %{"original_id" => 22, "type" => "hub", "data" => %{}}
      ],
      "connections" => [
        %{"source_node_index" => 0, "target_node_index" => 2, "source_pin" => "shared_response"}
      ],
      "localization" => []
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    [first_dialogue, second_dialogue | _rest] = normalized["nodes"]
    [first_response, duplicate_response] = first_dialogue["data"]["responses"]

    assert first_dialogue["data"]["localization_id"] == "shared_dialogue"
    assert second_dialogue["data"]["localization_id"] =~ "dialogue_legacy_"
    assert first_response["id"] == "shared_response"
    assert duplicate_response["id"] =~ "response_legacy_"
    assert hd(normalized["connections"])["source_pin"] == "shared_response"
  end

  test "normalization is deterministic and idempotent" do
    snapshot = %{
      "nodes" => [
        %{
          "original_id" => 30,
          "type" => "dialogue",
          "data" => %{"text" => "Legacy", "responses" => [%{"text" => "Continue"}]}
        }
      ],
      "connections" => [],
      "localization" => []
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)

    assert normalized == FlowSnapshotNormalizer.normalize(snapshot)
    assert normalized == FlowSnapshotNormalizer.normalize(normalized)
  end

  test "normalizes flow and top-level localization inside project snapshots" do
    snapshot = %{
      "flows" => [
        %{
          "id" => 40,
          "snapshot" => %{
            "nodes" => [
              %{
                "original_id" => 41,
                "type" => "dialogue",
                "data" => %{
                  "localization_id" => "dialogue.41",
                  "responses" => [%{"id" => "choice.41", "text" => "Continue"}]
                }
              }
            ],
            "connections" => [],
            "localization" => []
          }
        }
      ],
      "localization" => %{
        "texts" => [
          %{
            "source_type" => "flow_node",
            "source_id" => 41,
            "source_field" => "response.choice.41.text"
          }
        ]
      }
    }

    normalized = FlowSnapshotNormalizer.normalize_project(snapshot)

    assert get_in(normalized, ["flows", Access.at(0), "snapshot", "nodes", Access.at(0), "data", "localization_id"]) ==
             "dialogue_41"

    assert get_in(normalized, ["localization", "texts", Access.at(0), "source_field"]) ==
             "response.choice_41.text"
  end
end
