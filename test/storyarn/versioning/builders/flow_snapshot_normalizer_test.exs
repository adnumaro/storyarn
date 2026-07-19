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

  test "reserves valid ids before assigning sanitized legacy ids" do
    snapshot = %{
      "nodes" => [
        %{
          "original_id" => 23,
          "type" => "dialogue",
          "data" => %{
            "localization_id" => "stable.id",
            "responses" => [
              %{"id" => "stable.response", "text" => "Legacy"},
              %{"id" => "stable_response", "text" => "Current"}
            ]
          }
        },
        %{
          "original_id" => 24,
          "type" => "dialogue",
          "data" => %{"localization_id" => "stable_id", "responses" => []}
        },
        %{"original_id" => 25, "type" => "hub", "data" => %{}}
      ],
      "connections" => [
        %{"source_node_index" => 0, "target_node_index" => 2, "source_pin" => "stable.response"}
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    [legacy_dialogue, current_dialogue | _rest] = normalized["nodes"]
    [legacy_response, current_response] = legacy_dialogue["data"]["responses"]

    assert legacy_dialogue["data"]["localization_id"] =~ "dialogue_legacy_"
    assert current_dialogue["data"]["localization_id"] == "stable_id"
    assert legacy_response["id"] =~ "response_legacy_"
    assert current_response["id"] == "stable_response"
    assert hd(normalized["connections"])["source_pin"] == legacy_response["id"]
  end

  test "prefers an exact response id before interpreting the resp_ prefix" do
    snapshot = %{
      "nodes" => [
        %{
          "original_id" => 26,
          "type" => "dialogue",
          "data" => %{
            "localization_id" => "dialogue_26",
            "responses" => [%{"id" => "resp_bad.choice", "text" => "Continue"}]
          }
        },
        %{"original_id" => 27, "type" => "hub", "data" => %{}}
      ],
      "connections" => [
        %{"source_node_index" => 0, "target_node_index" => 1, "source_pin" => "resp_bad.choice"},
        %{"source_node_index" => 0, "target_node_index" => 1, "source_pin" => "resp_resp_bad.choice"}
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    [dialogue | _rest] = normalized["nodes"]
    [response] = dialogue["data"]["responses"]

    assert response["id"] == "resp_bad_choice"

    assert Enum.map(normalized["connections"], & &1["source_pin"]) == [
             "resp_bad_choice",
             "resp_resp_bad_choice"
           ]
  end

  test "reserves direct and prefixed connection ids per source node" do
    snapshot = %{
      "nodes" => [
        response_dialogue_node(28, "dialogue_28", "foo.bar"),
        response_dialogue_node(29, "dialogue_29", "bar.baz"),
        response_dialogue_node(30, "dialogue_30", "free.id"),
        %{"original_id" => 31, "type" => "hub", "data" => %{}}
      ],
      "connections" => [
        %{"source_node_index" => 0, "target_node_index" => 3, "source_pin" => "foo.bar"},
        %{"source_node_index" => 0, "target_node_index" => 3, "source_pin" => "foo_bar"},
        %{"source_node_index" => 0, "target_node_index" => 3, "source_pin" => "free_id"},
        %{"source_node_index" => 1, "target_node_index" => 3, "source_pin" => "resp_bar_baz"},
        %{"source_node_index" => 1, "target_node_index" => 3, "source_pin" => "bar.baz"},
        %{"source_node_index" => 2, "target_node_index" => 3, "source_pin" => "free.id"}
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    [first_dialogue, second_dialogue, third_dialogue | _rest] = normalized["nodes"]
    [first_response] = first_dialogue["data"]["responses"]
    [second_response] = second_dialogue["data"]["responses"]
    [third_response] = third_dialogue["data"]["responses"]

    assert first_response["id"] =~ "response_legacy_"
    assert second_response["id"] =~ "response_legacy_"
    assert third_response["id"] == "free_id"

    assert Enum.map(normalized["connections"], & &1["source_pin"]) == [
             first_response["id"],
             "foo_bar",
             "free_id",
             "resp_bar_baz",
             second_response["id"],
             "free_id"
           ]
  end

  test "reserves response ids referenced only by flow localization" do
    snapshot = %{
      "nodes" => [response_dialogue_node(32, "dialogue_32", "choice.one")],
      "localization" => [
        flow_node_localization_row(32, "response.choice_one.text"),
        flow_node_localization_row(32, "response.choice.one.text")
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize(snapshot)
    response_id = get_in(normalized, ["nodes", Access.at(0), "data", "responses", Access.at(0), "id"])

    assert response_id =~ "response_legacy_"

    assert Enum.map(normalized["localization"], & &1["source_field"]) == [
             "response.choice_one.text",
             "response.#{response_id}.text"
           ]
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

  test "generated dialogue ids stay stable when a node with an original id moves" do
    dialogue = %{
      "original_id" => 31,
      "type" => "dialogue",
      "data" => %{"text" => "Legacy", "responses" => []}
    }

    first_snapshot = %{"nodes" => [dialogue]}
    moved_snapshot = %{"nodes" => [%{"type" => "hub", "data" => %{}}, dialogue]}

    first_id =
      first_snapshot
      |> FlowSnapshotNormalizer.normalize()
      |> get_in(["nodes", Access.at(0), "data", "localization_id"])

    moved_id =
      moved_snapshot
      |> FlowSnapshotNormalizer.normalize()
      |> get_in(["nodes", Access.at(1), "data", "localization_id"])

    assert first_id == moved_id
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

  test "canonicalizes exact decimal entity ids and their dependent references" do
    snapshot = %{
      "original_id" => "40",
      "scene_id" => "8",
      "nodes" => [
        %{
          "original_id" => "41",
          "parent_id" => nil,
          "type" => "sequence",
          "data" => %{"audio_asset_id" => "9", "referenced_flow_id" => "42"},
          "sequence_tracks" => [%{"original_id" => "43", "asset_id" => "10"}],
          "sequence_visual_layers" => [%{"original_id" => "44", "asset_id" => "11"}]
        },
        %{
          "original_id" => "45",
          "parent_id" => "41",
          "type" => "hub",
          "data" => %{}
        }
      ],
      "connections" => [%{"original_id" => "46"}],
      "localization" => [
        %{"source_id" => "45", "speaker_sheet_id" => "12", "vo_asset_id" => "13"}
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize_entity_ids(snapshot)
    [sequence, child] = normalized["nodes"]

    assert normalized["original_id"] == 40
    assert normalized["scene_id"] == 8
    assert sequence["original_id"] == 41
    assert sequence["data"]["audio_asset_id"] == 9
    assert sequence["data"]["referenced_flow_id"] == 42
    assert hd(sequence["sequence_tracks"])["original_id"] == 43
    assert hd(sequence["sequence_tracks"])["asset_id"] == 10
    assert hd(sequence["sequence_visual_layers"])["original_id"] == 44
    assert hd(sequence["sequence_visual_layers"])["asset_id"] == 11
    assert child["original_id"] == 45
    assert child["parent_id"] == 41
    assert hd(normalized["connections"])["original_id"] == 46

    assert hd(normalized["localization"]) == %{
             "source_id" => 45,
             "speaker_sheet_id" => 12,
             "vo_asset_id" => 13
           }

    assert normalized == FlowSnapshotNormalizer.normalize_entity_ids(normalized)
  end

  test "leaves non-canonical entity ids for strict validation" do
    snapshot = %{
      "original_id" => " 40",
      "nodes" => [
        %{
          "original_id" => "forty-one",
          "parent_id" => "-1",
          "data" => %{"audio_asset_id" => "9.0"}
        }
      ]
    }

    assert FlowSnapshotNormalizer.normalize_entity_ids(snapshot) == snapshot
  end

  test "reserves response ids referenced only by project localization" do
    snapshot = %{
      "flows" => [
        %{
          "id" => 42,
          "snapshot" => %{
            "nodes" => [response_dialogue_node(43, "dialogue_43", "project.choice")]
          }
        }
      ],
      "localization" => %{
        "texts" => [
          flow_node_localization_row(43, "response.project_choice.text"),
          flow_node_localization_row(43, "response.project.choice.text")
        ]
      }
    }

    normalized = FlowSnapshotNormalizer.normalize_project(snapshot)

    response_id =
      get_in(normalized, [
        "flows",
        Access.at(0),
        "snapshot",
        "nodes",
        Access.at(0),
        "data",
        "responses",
        Access.at(0),
        "id"
      ])

    assert response_id =~ "response_legacy_"

    assert Enum.map(normalized["localization"]["texts"], & &1["source_field"]) == [
             "response.project_choice.text",
             "response.#{response_id}.text"
           ]
  end

  test "coordinates dialogue ids across project flows without adding localization" do
    snapshot = %{
      "flows" => [
        project_flow_entry(50, 51, "shared.dialogue"),
        project_flow_entry(52, 53, "shared_dialogue"),
        project_flow_entry(54, 55, "shared_dialogue")
      ]
    }

    normalized = FlowSnapshotNormalizer.normalize_project(snapshot)

    dialogue_ids =
      Enum.map(normalized["flows"], fn flow_entry ->
        get_in(flow_entry, ["snapshot", "nodes", Access.at(0), "data", "localization_id"])
      end)

    assert [legacy_id, "shared_dialogue", duplicate_id] = dialogue_ids
    assert legacy_id =~ "dialogue_legacy_"
    assert duplicate_id =~ "dialogue_legacy_"
    assert legacy_id != duplicate_id
    refute Map.has_key?(normalized, "localization")
    assert normalized == FlowSnapshotNormalizer.normalize_project(normalized)
  end

  test "preserves malformed collections instead of raising or inventing defaults" do
    flow_snapshot = %{
      "nodes" => [42],
      "connections" => ["malformed"],
      "localization" => :malformed
    }

    project_snapshot = %{
      "flows" => [nil, %{"snapshot" => nil}, %{"snapshot" => flow_snapshot}],
      "localization" => %{"texts" => nil}
    }

    assert FlowSnapshotNormalizer.normalize(%{"nodes" => nil}) == %{"nodes" => nil}
    assert FlowSnapshotNormalizer.normalize_project(%{"flows" => nil}) == %{"flows" => nil}
    assert FlowSnapshotNormalizer.normalize_project(project_snapshot) == project_snapshot
  end

  defp project_flow_entry(flow_id, node_id, localization_id) do
    %{
      "id" => flow_id,
      "snapshot" => %{
        "nodes" => [
          %{
            "original_id" => node_id,
            "type" => "dialogue",
            "data" => %{"localization_id" => localization_id, "responses" => []}
          }
        ]
      }
    }
  end

  defp response_dialogue_node(node_id, localization_id, response_id) do
    %{
      "original_id" => node_id,
      "type" => "dialogue",
      "data" => %{
        "localization_id" => localization_id,
        "responses" => [%{"id" => response_id, "text" => "Continue"}]
      }
    }
  end

  defp flow_node_localization_row(node_id, source_field) do
    %{
      "source_type" => "flow_node",
      "source_id" => node_id,
      "source_field" => source_field
    }
  end
end
