defmodule Storyarn.Projects.References.VariableReferenceValidationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Projects.References.VariableReferenceQueries
  alias Storyarn.Projects.References.VariableReferenceTracker
  alias Storyarn.Projects.References.VariableReferenceValidation
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneZone

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    # Create a sheet with shortcut "mc.jaime" and a number variable "health"
    sheet =
      sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

    health_block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    # Create a second sheet for variable_ref testing
    sheet2 =
      sheet_fixture(project, %{name: "Global Quests", shortcut: "global.quests"})

    quest_block =
      block_fixture(sheet2, %{
        type: "boolean",
        config: %{"label" => "Sword Done"}
      })

    %{
      scope: user_scope_fixture(user),
      project: project,
      flow: flow,
      sheet: sheet,
      health_block: health_block,
      sheet2: sheet2,
      quest_block: quest_block
    }
  end

  describe "strict snapshot variable validation" do
    test "accepts Scene display drafts but still rejects malformed display refs", ctx do
      changeset =
        SceneZone.update_changeset(
          %SceneZone{
            name: "Draft display",
            vertices: [
              %{"x" => 0, "y" => 0},
              %{"x" => 10, "y" => 0},
              %{"x" => 0, "y" => 10}
            ]
          },
          %{
            "action_type" => "display",
            "action_data" => %{"variable_ref" => "", "display_mode" => "value"}
          }
        )

      assert changeset.valid?

      for action_data <- [
            %{"variable_ref" => "", "display_mode" => "value"},
            %{"variable_ref" => nil, "display_mode" => "value"},
            %{"display_mode" => "value"}
          ] do
        assert :ok =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [
                     %{
                       source_type: "scene_zone",
                       source_id: 80,
                       action_type: "display",
                       action_data: action_data,
                       condition: nil
                     }
                   ]
                 )
      end

      assert {:error, {:malformed_variable_reference, "scene_zone", 80, :display_variable_ref, 123}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "scene_zone",
                     source_id: 80,
                     action_type: "display",
                     action_data: %{"variable_ref" => 123},
                     condition: nil
                   }
                 ]
               )
    end

    test "accepts Flow and Scene condition rules while their variable selection is incomplete", ctx do
      draft_condition =
        Flows.condition_sanitize(%{
          "logic" => "all",
          "blocks" => [
            %{
              "id" => "draft-block",
              "type" => "block",
              "logic" => "all",
              "rules" => [
                %{"id" => "empty", "sheet" => nil, "variable" => nil, "operator" => "equals", "value" => nil},
                %{"id" => "blank", "sheet" => "", "variable" => "", "operator" => "equals", "value" => nil},
                %{
                  "id" => "sheet-selected",
                  "sheet" => ctx.sheet.shortcut,
                  "variable" => nil,
                  "operator" => "equals",
                  "value" => nil
                }
              ]
            }
          ]
        })

      assert get_in(draft_condition, ["blocks", Access.at(0), "rules", Access.at(0), "sheet"]) == nil
      assert get_in(draft_condition, ["blocks", Access.at(0), "rules", Access.at(1), "variable"]) == ""

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "flow_node",
                     source_id: 81,
                     type: "condition",
                     data: %{"condition" => draft_condition}
                   },
                   %{
                     source_type: "scene_pin",
                     source_id: 82,
                     condition: draft_condition
                   }
                 ]
               )

      malformed_condition =
        put_in(
          draft_condition,
          ["blocks", Access.at(0), "rules", Access.at(0)],
          %{"sheet" => nil, "variable" => ctx.health_block.variable_name, "operator" => "equals"}
        )

      assert {:error, {:malformed_variable_reference, "flow_node", 81, :condition_rule, {nil, variable_name}}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "flow_node",
                     source_id: 81,
                     type: "condition",
                     data: %{"condition" => malformed_condition}
                   }
                 ]
               )

      assert variable_name == ctx.health_block.variable_name
    end

    test "accepts assignment targets and variable sources in writer-produced draft states", ctx do
      assignments =
        Flows.instruction_sanitize([
          %{
            "sheet" => nil,
            "variable" => nil,
            "operator" => "set",
            "value_type" => "literal",
            "value" => nil,
            "value_sheet" => nil
          },
          %{
            "sheet" => ctx.sheet.shortcut,
            "variable" => nil,
            "operator" => "set",
            "value_type" => "literal",
            "value" => nil,
            "value_sheet" => nil
          },
          %{
            "sheet" => ctx.sheet.shortcut,
            "variable" => ctx.health_block.variable_name,
            "operator" => "set",
            "value_type" => "variable_ref",
            "value" => nil,
            "value_sheet" => nil
          },
          %{
            "sheet" => ctx.sheet.shortcut,
            "variable" => ctx.health_block.variable_name,
            "operator" => "set",
            "value_type" => "variable_ref",
            "value" => nil,
            "value_sheet" => ctx.sheet2.shortcut
          }
        ])

      assert Enum.at(assignments, 0)["sheet"] == nil
      assert Enum.at(assignments, 0)["variable"] == nil
      assert Enum.at(assignments, 2)["value_sheet"] == nil
      assert Enum.at(assignments, 2)["value"] == nil

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "flow_node",
                     source_id: 83,
                     type: "instruction",
                     data: %{"assignments" => assignments}
                   },
                   %{
                     source_type: "scene_zone",
                     source_id: 84,
                     action_type: "action",
                     action_data: %{"assignments" => assignments},
                     condition: nil
                   }
                 ]
               )

      malformed =
        Flows.instruction_sanitize([
          %{
            "sheet" => nil,
            "variable" => ctx.health_block.variable_name,
            "operator" => "set",
            "value_type" => "literal",
            "value" => nil,
            "value_sheet" => nil
          }
        ])

      assert {:error, {:malformed_variable_reference, "flow_node", 83, :assignment_target, {nil, variable_name}}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "flow_node",
                     source_id: 83,
                     type: "instruction",
                     data: %{"assignments" => malformed}
                   }
                 ]
               )

      assert variable_name == ctx.health_block.variable_name
    end

    test "extracts Flow and every Scene variable-reference surface through one entity API", ctx do
      draft_condition =
        variable_condition(nil, nil)

      flow_snapshot = %{
        "nodes" => [
          %{
            "original_id" => 85,
            "type" => "condition",
            "data" => %{"condition" => draft_condition}
          }
        ]
      }

      scene_snapshot = %{
        "layers" => [
          %{
            "pins" => [%{"original_id" => 86, "condition" => draft_condition}],
            "zones" => [
              %{
                "original_id" => 87,
                "action_type" => "display",
                "action_data" => %{"variable_ref" => ""},
                "condition" => nil
              }
            ]
          }
        ],
        "orphan_pins" => [%{"original_id" => 88, "condition" => draft_condition}],
        "orphan_zones" => [
          %{
            "original_id" => 89,
            "action_type" => "action",
            "action_data" => %{
              "assignments" =>
                Flows.instruction_sanitize([
                  %{"sheet" => nil, "variable" => nil, "operator" => "set", "value_type" => "literal"}
                ])
            },
            "condition" => nil
          }
        ],
        "ambient_flows" => [
          %{
            "original_id" => 90,
            "trigger_type" => "on_event",
            "trigger_config" => %{"variable_ref" => ""}
          }
        ]
      }

      assert :ok =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "flow",
                 flow_snapshot
               )

      assert :ok =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "scene",
                 scene_snapshot
               )

      assert :ok =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "sheet",
                 %{}
               )

      invalid_scene_snapshot = put_in(scene_snapshot, ["layers", Access.at(0), "pins"], "not-a-list")

      assert {:error, {:invalid_variable_reference_snapshot_collection, "scene_layer", "pins", "not-a-list"}} =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "scene",
                 invalid_scene_snapshot
               )
    end

    test "entity extraction accepts valid snapshot members without variable references", ctx do
      flow_snapshot = %{
        "nodes" => [
          %{"original_id" => 91, "type" => "dialogue", "data" => %{"responses" => []}},
          %{"original_id" => 92, "type" => "condition", "data" => %{"condition" => nil}},
          %{"original_id" => 93, "type" => "instruction", "data" => %{"assignments" => []}},
          %{"original_id" => 94, "type" => "entry", "data" => %{}},
          %{"original_id" => 95, "type" => "hub", "data" => %{}}
        ]
      }

      scene_snapshot = %{
        "layers" => [
          %{
            "pins" => [%{"original_id" => 94, "condition" => nil}],
            "zones" => [
              %{
                "original_id" => 95,
                "action_type" => "action",
                "action_data" => %{"assignments" => []},
                "condition" => nil
              },
              %{
                "original_id" => 96,
                "action_type" => "collection",
                "action_data" => %{"items" => []},
                "condition" => nil
              }
            ]
          }
        ],
        "orphan_pins" => [%{"original_id" => 97, "condition" => nil}],
        "orphan_zones" => [],
        "ambient_flows" => [
          %{"original_id" => 98, "trigger_type" => "always", "trigger_config" => %{}},
          %{
            "original_id" => 99,
            "trigger_type" => "on_event",
            "trigger_config" => %{"variable_ref" => ""}
          }
        ]
      }

      assert :ok =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "flow",
                 flow_snapshot
               )

      assert :ok =
               VariableReferenceValidation.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "scene",
                 scene_snapshot
               )
    end

    test "entity preview and restore validation reject the same malformed Flow sources", ctx do
      cases = [
        {%{"original_id" => 100, "type" => "entry", "data" => nil},
         {:invalid_variable_reference_source, "flow_node", 100}},
        {%{"original_id" => 101, "type" => nil, "data" => %{}}, {:invalid_variable_reference_source, "flow_node", 101}},
        {%{"original_id" => "invalid", "type" => "entry", "data" => %{}},
         {:invalid_variable_reference_source, "flow_node", "invalid"}},
        {%{
           "original_id" => 102,
           "type" => "instruction",
           "data" => %{"assignments" => nil}
         }, {:malformed_variable_reference, "flow_node", 102, :assignments, nil}},
        {%{
           "original_id" => 103,
           "type" => "dialogue",
           "data" => %{"responses" => nil}
         }, {:malformed_variable_reference, "flow_node", 103, :dialogue_responses, nil}}
      ]

      for {node, reason} <- cases do
        assert {:error, ^reason} =
                 VariableReferenceValidation.validate_flow_node_variable_targets(
                   [node],
                   ctx.project.id
                 )

        assert {:error, ^reason} =
                 VariableReferenceValidation.validate_entity_snapshot_variable_references(
                   ctx.project.id,
                   "flow",
                   %{"nodes" => [node]}
                 )
      end
    end

    test "entity preview and restore validation reject the same malformed Scene action collections", ctx do
      cases = [
        {%{
           "original_id" => 104,
           "action_type" => "action",
           "action_data" => %{"assignments" => nil},
           "condition" => nil
         }, {:malformed_variable_reference, "scene_zone", 104, :assignments, nil}},
        {%{
           "original_id" => 105,
           "action_type" => "collection",
           "action_data" => %{"items" => nil},
           "condition" => nil
         }, {:malformed_variable_reference, "scene_zone", 105, :collection_items, nil}},
        {%{
           "original_id" => 106,
           "action_type" => "collection",
           "action_data" => %{"assignments" => []},
           "condition" => nil
         }, {:malformed_variable_reference, "scene_zone", 106, :collection_items, nil}},
        {%{
           "original_id" => 107,
           "action_type" => "collection",
           "action_data" => [],
           "condition" => nil
         }, {:invalid_variable_reference_source, "scene_zone", 107}}
      ]

      for {zone, reason} <- cases do
        restore_source = %{
          source_type: "scene_zone",
          source_id: zone["original_id"],
          action_type: zone["action_type"],
          action_data: zone["action_data"],
          condition: zone["condition"]
        }

        assert {:error, ^reason} =
                 run_variable_validation(fn ->
                   VariableReferenceValidation.validate_scene_element_variable_targets(
                     [zone],
                     ctx.project.id,
                     "scene_zone"
                   )
                 end)

        assert {:error, ^reason} =
                 run_variable_validation(fn ->
                   VariableReferenceValidation.validate_snapshot_variable_references(
                     ctx.project.id,
                     [restore_source]
                   )
                 end)

        assert {:error, ^reason} =
                 run_variable_validation(fn ->
                   VariableReferenceValidation.validate_entity_snapshot_variable_references(
                     ctx.project.id,
                     "scene",
                     scene_variable_snapshot([], [zone], [])
                   )
                 end)
      end
    end

    test "entity preview and restore validation reject the same malformed Scene source identities", ctx do
      zone = %{
        "original_id" => "invalid-zone",
        "action_type" => nil,
        "action_data" => %{},
        "condition" => nil
      }

      pin = %{"original_id" => "invalid-pin", "condition" => nil}

      ambient_flow = %{
        "original_id" => 108,
        "trigger_type" => nil,
        "trigger_config" => %{}
      }

      cases = [
        {
          %{
            source_type: "scene_zone",
            source_id: zone["original_id"],
            action_type: zone["action_type"],
            action_data: zone["action_data"],
            condition: zone["condition"]
          },
          scene_variable_snapshot([], [zone], []),
          {:invalid_variable_reference_source, "scene_zone", "invalid-zone"}
        },
        {%{
           source_type: "scene_pin",
           source_id: pin["original_id"],
           action_type: nil,
           action_data: nil,
           condition: pin["condition"]
         }, scene_variable_snapshot([pin], [], []), {:invalid_variable_reference_source, "scene_pin", "invalid-pin"}},
        {%{
           source_type: "scene_ambient_flow",
           source_id: ambient_flow["original_id"],
           trigger_type: ambient_flow["trigger_type"],
           trigger_config: ambient_flow["trigger_config"]
         }, scene_variable_snapshot([], [], [ambient_flow]),
         {:invalid_variable_reference_source, "scene_ambient_flow", 108}}
      ]

      for {restore_source, snapshot, reason} <- cases do
        assert {:error, ^reason} =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [restore_source]
                 )

        assert {:error, ^reason} =
                 VariableReferenceValidation.validate_entity_snapshot_variable_references(
                   ctx.project.id,
                   "scene",
                   snapshot
                 )
      end
    end

    test "validates every authoritative dialogue response variable surface", ctx do
      valid_condition = variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)
      valid_assignment = variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)

      source = %{
        source_type: "flow_node",
        source_id: 90,
        type: "dialogue",
        data: %{
          "responses" => [
            %{
              "condition" => Jason.encode!(valid_condition),
              "instruction_assignments" => [valid_assignment]
            },
            %{
              "condition" => nil,
              "instruction_assignments" => [],
              "instruction" => Jason.encode!([valid_assignment])
            }
          ]
        }
      }

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [source]
               )

      invalid_sources = [
        put_in(
          source,
          [:data, "responses", Access.at(0), "condition"],
          Jason.encode!(variable_condition(ctx.sheet.shortcut, "missing_condition"))
        ),
        put_in(
          source,
          [:data, "responses", Access.at(0), "instruction_assignments", Access.at(0), "variable"],
          "missing_structured"
        ),
        put_in(
          source,
          [:data, "responses", Access.at(1), "instruction"],
          Jason.encode!([variable_assignment(ctx.sheet.shortcut, "missing_legacy")])
        )
      ]

      for invalid <- invalid_sources do
        assert {:error, {:unresolved_variable_reference, "flow_node", 90, _kind, "mc.jaime", missing}} =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [invalid]
                 )

        assert missing in ~w(missing_condition missing_structured missing_legacy)
      end
    end

    test "accepts resolvable Flow refs and rejects unresolved or malformed ones", ctx do
      valid_source = %{
        source_type: "flow_node",
        source_id: 91,
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "sheet" => ctx.sheet.shortcut,
              "variable" => ctx.health_block.variable_name,
              "value_type" => "variable_ref",
              "value_sheet" => ctx.sheet2.shortcut,
              "value" => ctx.quest_block.variable_name
            }
          ]
        }
      }

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [valid_source]
               )

      unresolved =
        put_in(
          valid_source,
          [:data, "assignments", Access.at(0), "variable"],
          "missing_variable"
        )

      assert {:error, {:unresolved_variable_reference, "flow_node", 91, "write", source_sheet, "missing_variable"}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [unresolved]
               )

      assert source_sheet == ctx.sheet.shortcut

      malformed =
        put_in(valid_source, [:data, "assignments", Access.at(0), "value_sheet"], nil)

      assert {:error, {:malformed_variable_reference, "flow_node", 91, :assignment_value, {nil, source_variable}}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [malformed]
               )

      assert source_variable == ctx.quest_block.variable_name
    end

    test "uses the same strict resolver for Scene sources", ctx do
      source = %{
        source_type: "scene_zone",
        source_id: 92,
        action_type: "action",
        action_data: %{
          "assignments" => [
            %{
              "sheet" => ctx.sheet.shortcut,
              "variable" => ctx.health_block.variable_name,
              "value_type" => "literal"
            }
          ]
        },
        condition: nil
      }

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [source]
               )

      invalid = put_in(source, [:action_data, "assignments", Access.at(0), "variable"], "gone")

      assert {:error, {:unresolved_variable_reference, "scene_zone", 92, "write", source_sheet, "gone"}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [invalid]
               )

      assert source_sheet == ctx.sheet.shortcut
    end

    test "validates and indexes collection item conditions and instructions", ctx do
      scene = scene_fixture(ctx.project)
      condition = variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)

      assignment =
        ctx.sheet.shortcut
        |> variable_assignment(ctx.health_block.variable_name)
        |> Map.merge(%{
          "value_type" => "variable_ref",
          "value_sheet" => ctx.sheet2.shortcut,
          "value" => ctx.quest_block.variable_name
        })

      action_data = %{
        "items" => [
          %{
            "id" => Ecto.UUID.generate(),
            "condition" => condition,
            "instruction" => %{"assignments" => [assignment]}
          },
          %{"id" => Ecto.UUID.generate(), "condition" => nil},
          %{"id" => Ecto.UUID.generate(), "condition" => %{}, "instruction" => %{}}
        ]
      }

      zone =
        zone_fixture(scene, %{
          "action_type" => "collection",
          "action_data" => action_data
        })

      source = %{
        source_type: "scene_zone",
        source_id: zone.id,
        action_type: "collection",
        action_data: action_data,
        condition: nil
      }

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [source]
               )

      assert :ok =
               VariableReferenceTracker.update_scene_zone_references(
                 zone,
                 project_id: ctx.project.id
               )

      indexed_references = fn ->
        from(reference in VariableReference,
          where:
            reference.source_type == "scene_zone" and
              reference.source_id == ^zone.id,
          select: {reference.block_id, reference.kind}
        )
        |> Repo.all()
        |> MapSet.new()
      end

      expected_references =
        MapSet.new([
          {ctx.health_block.id, "read"},
          {ctx.health_block.id, "write"},
          {ctx.quest_block.id, "read"}
        ])

      assert indexed_references.() == expected_references

      invalid_sources = [
        put_in(
          source,
          [:action_data, "items", Access.at(0), "condition", "blocks", Access.at(0), "rules", Access.at(0), "variable"],
          "missing_collection_condition"
        ),
        put_in(
          source,
          [:action_data, "items", Access.at(0), "instruction", "assignments", Access.at(0), "variable"],
          "missing_collection_write"
        ),
        put_in(
          source,
          [:action_data, "items", Access.at(0), "instruction", "assignments", Access.at(0), "value"],
          "missing_collection_value"
        )
      ]

      for invalid_source <- invalid_sources do
        assert {:error, {:unresolved_variable_reference, "scene_zone", source_id, _kind, _source_sheet, missing_variable}} =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [invalid_source]
                 )

        assert source_id == zone.id

        assert missing_variable in [
                 "missing_collection_condition",
                 "missing_collection_write",
                 "missing_collection_value"
               ]

        assert indexed_references.() == expected_references
      end

      malformed = put_in(source, [:action_data, "items"], ["not-an-item-map"])

      assert {:error, {:malformed_variable_reference, "scene_zone", source_id, {:collection_item, 0}, "not-an-item-map"}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [malformed]
               )

      assert source_id == zone.id
      assert indexed_references.() == expected_references
    end

    test "rejects constant Blocks and constant table columns as variable targets", ctx do
      constant_block =
        block_fixture(ctx.sheet, %{
          type: "number",
          is_constant: true,
          config: %{"label" => "Authored constant"}
        })

      table = table_block_fixture(ctx.sheet, %{label: "Runtime stats"})
      [column | _rest] = table.table_columns
      [row | _rest] = table.table_rows

      column =
        column
        |> Ecto.Changeset.change(type: "number", is_constant: true)
        |> Repo.update!()

      invalid_sources = [
        %{
          source_type: "flow_node",
          source_id: 95,
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(ctx.sheet.shortcut, constant_block.variable_name)
            ]
          }
        },
        %{
          source_type: "scene_zone",
          source_id: 96,
          action_type: "display",
          action_data: %{
            "variable_ref" => "#{ctx.sheet.shortcut}.#{table.variable_name}.#{row.slug}.#{column.slug}"
          },
          condition: nil
        }
      ]

      for source <- invalid_sources do
        assert {:error,
                {:unresolved_variable_reference, _source_type, _source_id, _kind, _source_sheet, _source_variable}} =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [source]
                 )
      end
    end

    test "resolves dotted shortcuts exactly for Scene display and ambient refs", ctx do
      sources = [
        %{
          source_type: "scene_zone",
          source_id: 93,
          action_type: "display",
          action_data: %{"variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.health_block.variable_name}"},
          condition: nil
        },
        %{
          source_type: "scene_ambient_flow",
          source_id: 94,
          trigger_type: "on_event",
          trigger_config: %{"variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.health_block.variable_name}"}
        }
      ]

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 sources
               )

      invalid = put_in(hd(sources), [:action_data, "variable_ref"], "#{ctx.sheet.shortcut}.missing")

      assert {:error, {:unresolved_variable_reference, "scene_zone", 93, "read", "mc.jaime", "missing"}} =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [invalid]
               )
    end

    test "accepts draft on-event ambient triggers without a variable reference", ctx do
      trigger_configs = [
        %{"variable_ref" => nil},
        %{"variable_ref" => ""},
        %{}
      ]

      sources =
        trigger_configs
        |> Enum.with_index(100)
        |> Enum.map(fn {trigger_config, source_id} ->
          changeset =
            SceneAmbientFlow.changeset(%SceneAmbientFlow{}, %{
              "flow_id" => ctx.flow.id,
              "trigger_type" => "on_event",
              "trigger_config" => trigger_config
            })

          assert changeset.valid?

          %{
            source_type: "scene_ambient_flow",
            source_id: source_id,
            trigger_type: "on_event",
            trigger_config: trigger_config
          }
        end)

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 sources
               )

      assert :ok =
               VariableReferenceValidation.validate_snapshot_variable_references(
                 ctx.project.id,
                 [
                   %{
                     source_type: "scene_ambient_flow",
                     source_id: 103,
                     trigger_type: "on_event"
                   }
                 ]
               )
    end

    test "rejects present non-map on-event ambient trigger configs", ctx do
      invalid_configs = ["not-a-config", [], 123, false, nil]

      for {trigger_config, source_id} <- Enum.with_index(invalid_configs, 104) do
        assert {:error, {:invalid_variable_reference_source, "scene_ambient_flow", ^source_id}} =
                 VariableReferenceValidation.validate_snapshot_variable_references(
                   ctx.project.id,
                   [
                     %{
                       source_type: "scene_ambient_flow",
                       source_id: source_id,
                       trigger_type: "on_event",
                       trigger_config: trigger_config
                     }
                   ]
                 )
      end
    end

    test "indexes a dotted Scene display ref without splitting the shortcut", ctx do
      scene = scene_fixture(ctx.project)

      zone =
        zone_fixture(scene, %{
          "action_type" => "display",
          "action_data" => %{
            "variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.health_block.variable_name}"
          }
        })

      assert :ok =
               VariableReferenceTracker.update_scene_zone_references(
                 zone,
                 project_id: ctx.project.id
               )

      assert %VariableReference{
               source_type: "scene_zone",
               source_id: source_id,
               block_id: block_id,
               kind: "read",
               source_sheet: "mc.jaime",
               source_variable: "health"
             } =
               Repo.one!(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "scene_zone" and
                       reference.source_id == ^zone.id
                 )
               )

      assert source_id == zone.id
      assert block_id == ctx.health_block.id
    end

    test "qualified Scene refs prefer an explicit numeric shortcut over an ID fallback", ctx do
      fallback_sheet = sheet_fixture(ctx.project, %{name: "Fallback"})
      explicit_sheet = sheet_fixture(ctx.project, %{name: "Explicit"})
      namespace = Integer.to_string(fallback_sheet.id)

      Repo.update!(Ecto.Changeset.change(fallback_sheet, shortcut: nil))
      Repo.update!(Ecto.Changeset.change(explicit_sheet, shortcut: namespace))

      _fallback_block =
        block_fixture(fallback_sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      explicit_block =
        block_fixture(explicit_sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      fallback_table = table_block_fixture(fallback_sheet, %{label: "Inventory"})
      explicit_table = table_block_fixture(explicit_sheet, %{label: "Inventory"})
      [fallback_row] = fallback_table.table_rows
      [fallback_column] = fallback_table.table_columns
      [explicit_row] = explicit_table.table_rows
      [explicit_column] = explicit_table.table_columns

      assert {fallback_table.variable_name, fallback_row.slug, fallback_column.slug} ==
               {explicit_table.variable_name, explicit_row.slug, explicit_column.slug}

      scene = scene_fixture(ctx.project)

      refs = [
        "#{namespace}.#{explicit_block.variable_name}",
        "#{namespace}.#{explicit_table.variable_name}.#{explicit_row.slug}.#{explicit_column.slug}"
      ]

      resolved_block_ids =
        Enum.map(refs, fn variable_ref ->
          zone =
            zone_fixture(scene, %{
              "action_type" => "display",
              "action_data" => %{"variable_ref" => variable_ref}
            })

          assert :ok =
                   VariableReferenceTracker.update_scene_zone_references(
                     zone,
                     project_id: ctx.project.id
                   )

          Repo.one!(
            from(reference in VariableReference,
              where:
                reference.source_type == "scene_zone" and
                  reference.source_id == ^zone.id,
              select: reference.block_id
            )
          )
        end)

      assert resolved_block_ids == [explicit_block.id, explicit_table.id]
    end

    test "a fallback reference becomes stale and rebuilds to a new explicit numeric owner", ctx do
      fallback_sheet = sheet_fixture(ctx.project, %{name: "Fallback"})
      namespace = Integer.to_string(fallback_sheet.id)
      Repo.update!(Ecto.Changeset.change(fallback_sheet, shortcut: nil))

      fallback_block =
        block_fixture(fallback_sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [variable_assignment(namespace, fallback_block.variable_name)]
          }
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      explicit_sheet = sheet_fixture(ctx.project, %{name: "Explicit", shortcut: namespace})

      explicit_block =
        block_fixture(explicit_sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      assert [%{stale: true}] =
               VariableReferenceQueries.check_stale_references(
                 fallback_block.id,
                 ctx.project.id
               )

      assert :ok = VariableReferenceTracker.rebuild_project_variable_references(ctx.project.id)

      rebuilt_block_ids =
        from(reference in VariableReference,
          where:
            reference.source_type == "flow_node" and
              reference.source_id == ^node.id,
          select: reference.block_id
        )
        |> Repo.all()
        |> MapSet.new()

      assert rebuilt_block_ids == MapSet.new([fallback_block.id, explicit_block.id])

      assert [%{stale: false}] =
               VariableReferenceQueries.check_stale_references(
                 explicit_block.id,
                 ctx.project.id
               )
    end

    test "indexes, deletes, and rebuilds dotted ambient event refs", ctx do
      scene = scene_fixture(ctx.project)
      linked_flow = flow_fixture(ctx.project)

      ambient_flow =
        Repo.insert!(%SceneAmbientFlow{
          scene_id: scene.id,
          flow_id: linked_flow.id,
          trigger_type: "on_event",
          trigger_config: %{"variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.health_block.variable_name}"},
          enabled: true,
          priority: 0,
          position: 0
        })

      assert :ok =
               VariableReferenceTracker.update_scene_ambient_flow_references(
                 ambient_flow,
                 project_id: ctx.project.id
               )

      assert %VariableReference{
               source_type: "scene_ambient_flow",
               source_id: source_id,
               block_id: block_id,
               kind: "read",
               source_sheet: "mc.jaime",
               source_variable: "health"
             } =
               Repo.one!(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "scene_ambient_flow" and
                       reference.source_id == ^ambient_flow.id
                 )
               )

      assert source_id == ambient_flow.id
      assert block_id == ctx.health_block.id

      assert [%{source_type: "scene_ambient_flow", ambient_flow_id: ambient_flow_id}] =
               VariableReferenceQueries.get_variable_usage(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert ambient_flow_id == ambient_flow.id

      assert [%{source_type: "scene_ambient_flow", stale: false}] =
               VariableReferenceQueries.check_stale_references(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.jaime.renamed"})

      assert [%{source_type: "scene_ambient_flow", stale: true}] =
               VariableReferenceQueries.check_stale_references(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert VariableReferenceQueries.count_stale_references(
               [ctx.health_block.id],
               ctx.project.id
             ) == %{ctx.health_block.id => 1}

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.jaime"})

      # Simulate a missing derived projection row. Ordinary deletion belongs to
      # Scenes; this Projects test is concerned only with project-wide repair.
      assert {1, nil} =
               Repo.delete_all(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "scene_ambient_flow" and
                       reference.source_id == ^ambient_flow.id
                 )
               )

      refute Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "scene_ambient_flow" and
                     reference.source_id == ^ambient_flow.id
               )
             )

      assert :ok = VariableReferenceTracker.rebuild_project_variable_references(ctx.project.id)

      assert Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "scene_ambient_flow" and
                     reference.source_id == ^ambient_flow.id and
                     reference.block_id == ^ctx.health_block.id
               )
             )
    end
  end

  describe "flow_node_references_current_ids/2" do
    test "certifies regular and table references in one batch and rejects stale metadata", ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      table_row = table_row_fixture(table_block, %{name: "Strength"})
      table_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      regular_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)
            ]
          }
        })

      table_variable =
        "#{table_block.variable_name}.#{table_row.slug}.#{table_column.slug}"

      table_node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{"condition" => variable_condition(ctx.sheet.shortcut, table_variable)}
        })

      assert :ok = VariableReferenceTracker.update_references(regular_node)
      assert :ok = VariableReferenceTracker.update_references(table_node)

      assert VariableReferenceValidation.flow_node_references_current_ids(
               [regular_node, table_node],
               ctx.project.id
             ) == MapSet.new([regular_node.id, table_node.id])

      other_project = project_fixture()

      assert VariableReferenceValidation.flow_node_references_current_ids(
               [regular_node, table_node],
               other_project.id
             ) == MapSet.new()

      table_reference =
        Repo.get_by!(VariableReference,
          source_type: "flow_node",
          source_id: table_node.id,
          block_id: table_block.id,
          kind: "read"
        )

      table_reference
      |> Ecto.Changeset.change(source_sheet: "stale")
      |> Repo.update!()

      assert VariableReferenceValidation.flow_node_references_current_ids(
               [regular_node, table_node],
               ctx.project.id
             ) == MapSet.new([regular_node.id])
    end
  end

  # -- Table variable tests --

  defp variable_assignment(sheet_shortcut, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }
  end

  defp variable_condition(sheet_shortcut, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        }
      ]
    }
  end

  defp scene_variable_snapshot(pins, zones, ambient_flows) do
    %{
      "layers" => [%{"pins" => pins, "zones" => zones}],
      "orphan_pins" => [],
      "orphan_zones" => [],
      "ambient_flows" => ambient_flows
    }
  end

  defp run_variable_validation(validation) do
    task = Task.async(validation)

    case Task.yield(task, 1_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> flunk("variable-reference validation did not terminate")
    end
  end
end
