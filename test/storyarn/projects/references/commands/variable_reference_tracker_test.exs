defmodule Storyarn.Projects.References.VariableReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: ProjectFlowNodeRecord
  alias Storyarn.Projects.References
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Projects.References.VariableReferenceTracker
  alias Storyarn.Projects.References.VariableReferenceValidation
  alias Storyarn.Sheets.Block

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

  describe "rebuild_project_variable_references/1" do
    test "rebuilds flow, pin, and zone references after a target block is reinserted", ctx do
      condition = variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)
      assignment = variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)

      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      scene = scene_fixture(ctx.project)
      pin = pin_fixture(scene, %{"condition" => condition})

      zone =
        zone_fixture(scene, %{
          "action_type" => "action",
          "action_data" => %{"assignments" => [assignment]}
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      assert source_identities(ctx.health_block.id) ==
               MapSet.new([
                 {"flow_node", node.id},
                 {"scene_pin", pin.id},
                 {"scene_zone", zone.id}
               ])

      Repo.delete!(ctx.health_block)
      assert source_identities(ctx.health_block.id) == MapSet.new()
      reinsert_block(ctx.health_block)

      assert :ok = References.rebuild_project_variable_references(ctx.project.id)

      assert source_identities(ctx.health_block.id) ==
               MapSet.new([
                 {"flow_node", node.id},
                 {"scene_pin", pin.id},
                 {"scene_zone", zone.id}
               ])
    end

    test "does not rebuild sources in deleted roots or soft-deleted flow nodes", ctx do
      condition = variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)
      assignment = variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)

      active_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      deleted_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      deleted_flow = flow_fixture(ctx.project)

      deleted_root_node =
        node_fixture(deleted_flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      active_scene = scene_fixture(ctx.project)
      active_pin = pin_fixture(active_scene, %{"condition" => condition})

      active_zone =
        zone_fixture(active_scene, %{
          "action_type" => "action",
          "action_data" => %{"assignments" => [assignment]}
        })

      deleted_scene = scene_fixture(ctx.project)
      deleted_root_pin = pin_fixture(deleted_scene, %{"condition" => condition})

      deleted_root_zone =
        zone_fixture(deleted_scene, %{
          "action_type" => "action",
          "action_data" => %{"assignments" => [assignment]}
        })

      for node <- [active_node, deleted_node, deleted_root_node] do
        assert :ok = VariableReferenceTracker.update_references(node)
      end

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
      Repo.update!(Ecto.Changeset.change(deleted_node, deleted_at: deleted_at))
      Repo.update!(Ecto.Changeset.change(deleted_flow, deleted_at: deleted_at))
      Repo.update!(Ecto.Changeset.change(deleted_scene, deleted_at: deleted_at))

      Repo.delete!(ctx.health_block)
      assert source_identities(ctx.health_block.id) == MapSet.new()
      reinsert_block(ctx.health_block)

      assert :ok =
               VariableReferenceTracker.rebuild_project_variable_references(ctx.project.id)

      identities = source_identities(ctx.health_block.id)

      assert identities ==
               MapSet.new([
                 {"flow_node", active_node.id},
                 {"scene_pin", active_pin.id},
                 {"scene_zone", active_zone.id}
               ])

      refute MapSet.member?(identities, {"flow_node", deleted_node.id})
      refute MapSet.member?(identities, {"flow_node", deleted_root_node.id})
      refute MapSet.member?(identities, {"scene_pin", deleted_root_pin.id})
      refute MapSet.member?(identities, {"scene_zone", deleted_root_zone.id})
    end

    test "preserves stale rows when restored Sheet names no longer resolve from source data", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)
            ]
          }
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      [reference_before] =
        Repo.all(
          from(reference in VariableReference,
            where:
              reference.source_type == "flow_node" and
                reference.source_id == ^node.id
          )
        )

      Repo.update!(Ecto.Changeset.change(ctx.sheet, shortcut: "restored-sheet"))

      Repo.update!(Ecto.Changeset.change(ctx.health_block, variable_name: "restored-health"))

      assert :ok =
               VariableReferenceTracker.rebuild_project_variable_references(ctx.project.id)

      assert [reference_after] =
               Repo.all(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "flow_node" and
                       reference.source_id == ^node.id
                 )
               )

      assert reference_after.id == reference_before.id
      assert reference_after.block_id == ctx.health_block.id
      assert reference_after.source_sheet == reference_before.source_sheet
      assert reference_after.source_variable == reference_before.source_variable
    end
  end

  describe "update_references/1 with instruction nodes" do
    test "accepts a Project-owned structural Flow node record", ctx do
      persisted_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(
                ctx.sheet.shortcut,
                ctx.health_block.variable_name
              )
            ]
          }
        })

      node =
        %ProjectFlowNodeRecord{
          id: persisted_node.id,
          flow_id: ctx.flow.id,
          type: persisted_node.type,
          data: persisted_node.data
        }

      assert :ok = VariableReferenceTracker.update_references(node)

      assert :ok =
               VariableReferenceValidation.validate_flow_node_variable_targets(
                 [node],
                 ctx.project.id
               )

      assert [%VariableReference{} = reference] = Repo.all(VariableReference)
      assert reference.source_id == node.id
      assert reference.flow_node_id == node.id
      assert reference.block_id == ctx.health_block.id
    end

    test "creates write reference for literal assignment", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.flow_node_id == node.id
      assert ref.block_id == ctx.health_block.id
      assert ref.kind == "write"
    end

    test "creates write AND read references for variable_ref assignment", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "sword_done",
                "value_type" => "variable_ref",
                "value_sheet" => "global.quests"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = VariableReference |> Repo.all() |> Enum.sort_by(& &1.kind)
      assert length(refs) == 2

      read_ref = Enum.find(refs, &(&1.kind == "read"))
      write_ref = Enum.find(refs, &(&1.kind == "write"))

      assert read_ref.block_id == ctx.quest_block.id
      assert write_ref.block_id == ctx.health_block.id
      assert read_ref.flow_node_id == node.id
      assert write_ref.flow_node_id == node.id
    end

    test "unresolvable variable creates no reference", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "nonexistent.sheet",
                "variable" => "nope",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      assert Repo.all(VariableReference) == []
    end

    test "unresolvable variable_ref source creates write ref but no read ref", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "nonexistent_var",
                "value_type" => "variable_ref",
                "value_sheet" => "nonexistent.sheet"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.kind == "write"
      assert ref.block_id == ctx.health_block.id
    end

    test "stores source_sheet and source_variable on write reference", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      ref = Repo.one!(VariableReference)
      assert ref.source_sheet == "mc.jaime"
      assert ref.source_variable == "health"
    end

    test "stores source_sheet and source_variable on read reference from variable_ref", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "sword_done",
                "value_type" => "variable_ref",
                "value_sheet" => "global.quests"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      read_ref = VariableReference |> Repo.all() |> Enum.find(&(&1.kind == "read"))
      assert read_ref.source_sheet == "global.quests"
      assert read_ref.source_variable == "sword_done"
    end
  end

  describe "update_references/1 with condition nodes" do
    test "creates read references from condition rules", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "b1",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "id" => "rule_1",
                      "sheet" => "mc.jaime",
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => "50"
                    }
                  ]
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.flow_node_id == node.id
      assert ref.block_id == ctx.health_block.id
      assert ref.kind == "read"
    end

    test "creates multiple read references from multiple rules", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "b1",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "id" => "rule_1",
                      "sheet" => "mc.jaime",
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => "50"
                    },
                    %{
                      "id" => "rule_2",
                      "sheet" => "global.quests",
                      "variable" => "sword_done",
                      "operator" => "is_true",
                      "value" => nil
                    }
                  ]
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 2
      assert Enum.all?(refs, &(&1.kind == "read"))

      block_ids = refs |> Enum.map(& &1.block_id) |> Enum.sort()
      expected = Enum.sort([ctx.health_block.id, ctx.quest_block.id])
      assert block_ids == expected
    end

    test "stores source_sheet and source_variable on condition read reference", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "b1",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "id" => "rule_1",
                      "sheet" => "mc.jaime",
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => "50"
                    }
                  ]
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      ref = Repo.one!(VariableReference)
      assert ref.source_sheet == "mc.jaime"
      assert ref.source_variable == "health"
    end
  end

  describe "update_references/1 replaces old references" do
    test "updating node replaces old references", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)
      assert length(Repo.all(VariableReference)) == 1

      # Update to reference a different variable
      {:ok, _updated_node, _} =
        Flows.update_node_data(node, %{
          "assignments" => [
            %{
              "id" => "assign_2",
              "sheet" => "global.quests",
              "variable" => "sword_done",
              "operator" => "set_true",
              "value_type" => "literal"
            }
          ]
        })

      # update_node_data already calls update_references via NodeCrud integration
      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.block_id == ctx.quest_block.id
      assert ref.kind == "write"
    end
  end

  describe "update_references/1 with non-referencing node types" do
    test "dialogue node creates no references", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "speaker" => "Character"}
        })

      VariableReferenceTracker.update_references(node)

      assert Repo.all(VariableReference) == []
    end
  end

  describe "deleting node cascades reference deletion" do
    test "references auto-deleted via DB cascade when node is deleted", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)
      assert length(Repo.all(VariableReference)) == 1

      {:ok, _deleted_node, _meta} = Flows.delete_node(node)
      assert Repo.all(VariableReference) == []
    end
  end

  describe "deleting block cascades reference deletion" do
    test "references auto-deleted via DB cascade when block is deleted", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)
      assert length(Repo.all(VariableReference)) == 1

      # Hard-delete the block to trigger cascade
      Repo.delete!(ctx.health_block)
      assert Repo.all(VariableReference) == []
    end
  end

  describe "update_references with table variable instruction nodes" do
    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      strength_row = table_row_fixture(table_block, %{name: "Strength"})
      value_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      # Also add a second cell for multi-cell tests
      wisdom_row = table_row_fixture(table_block, %{name: "Wisdom"})

      Map.merge(ctx, %{
        table_block: table_block,
        strength_row: strength_row,
        wisdom_row: wisdom_row,
        value_column: value_column
      })
    end

    test "creates write ref for table variable assignment", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "attributes.strength.value",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.flow_node_id == node.id
      assert ref.block_id == ctx.table_block.id
      assert ref.kind == "write"
      assert ref.source_sheet == "mc.jaime"
      assert ref.source_variable == "attributes.strength.value"
    end

    test "creates read ref for table variable_ref", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "attributes.strength.value",
                "value_type" => "variable_ref",
                "value_sheet" => "mc.jaime"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = VariableReference |> Repo.all() |> Enum.sort_by(& &1.kind)
      assert length(refs) == 2

      read_ref = Enum.find(refs, &(&1.kind == "read"))
      write_ref = Enum.find(refs, &(&1.kind == "write"))

      assert read_ref.block_id == ctx.table_block.id
      assert read_ref.source_variable == "attributes.strength.value"
      assert write_ref.block_id == ctx.health_block.id
    end

    test "multiple cells from same table block are stored as separate refs", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "attributes.strength.value",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              },
              %{
                "id" => "assign_2",
                "sheet" => "mc.jaime",
                "variable" => "attributes.wisdom.value",
                "operator" => "set",
                "value" => "8",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 2

      # Both point to same block_id (the table block)
      assert Enum.all?(refs, &(&1.block_id == ctx.table_block.id))
      assert Enum.all?(refs, &(&1.kind == "write"))

      variables = refs |> Enum.map(& &1.source_variable) |> Enum.sort()
      assert variables == ["attributes.strength.value", "attributes.wisdom.value"]
    end
  end

  describe "update_references with table variable condition nodes" do
    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      strength_row = table_row_fixture(table_block, %{name: "Strength"})
      _value_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      Map.merge(ctx, %{
        table_block: table_block,
        strength_row: strength_row
      })
    end

    test "creates read ref from condition rule with table variable", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "b1",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "id" => "rule_1",
                      "sheet" => "mc.jaime",
                      "variable" => "attributes.strength.value",
                      "operator" => "greater_than",
                      "value" => "5"
                    }
                  ]
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 1

      ref = hd(refs)
      assert ref.block_id == ctx.table_block.id
      assert ref.kind == "read"
      assert ref.source_variable == "attributes.strength.value"
    end
  end

  describe "update_references/1 with dialogue nodes" do
    test "indexes response conditions, structured assignments, and legacy instruction JSON", ctx do
      legacy_block =
        block_fixture(ctx.sheet2, %{
          type: "number",
          config: %{"label" => "Legacy count", "placeholder" => "0"}
        })

      node =
        node_fixture(ctx.flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{
                "id" => "structured",
                "text" => "Structured",
                "condition" => Jason.encode!(variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)),
                "instruction_assignments" => [
                  variable_assignment(ctx.sheet2.shortcut, ctx.quest_block.variable_name)
                ]
              },
              %{
                "id" => "legacy",
                "text" => "Legacy",
                "instruction_assignments" => [],
                "instruction" =>
                  Jason.encode!([
                    variable_assignment(ctx.sheet2.shortcut, legacy_block.variable_name)
                  ])
              }
            ]
          }
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      assert from(reference in VariableReference,
               where: reference.source_type == "flow_node" and reference.source_id == ^node.id,
               select: {reference.block_id, reference.kind}
             )
             |> Repo.all()
             |> MapSet.new() ==
               MapSet.new([
                 {ctx.health_block.id, "read"},
                 {ctx.quest_block.id, "write"},
                 {legacy_block.id, "write"}
               ])
    end

    test "dialogue node produces no variable references", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello world</p>",
            "speaker_sheet_id" => nil,
            "responses" => []
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(from(vr in VariableReference, where: vr.flow_node_id == ^node.id))

      assert refs == []
    end

    test "hub node produces no variable references", ctx do
      {:ok, node} =
        Flows.create_node(ctx.flow, %{
          type: "hub",
          data: %{"hub_id" => "test_hub_refs", "label" => "Test"}
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(from(vr in VariableReference, where: vr.flow_node_id == ^node.id))

      assert refs == []
    end
  end

  describe "Scene reference query batching" do
    test "keeps query count constant as collection references grow", ctx do
      scene = scene_fixture(ctx.project)
      condition = variable_condition(ctx.sheet.shortcut, ctx.health_block.variable_name)

      collection_item = fn ->
        assignment =
          ctx.sheet.shortcut
          |> variable_assignment(ctx.health_block.variable_name)
          |> Map.merge(%{
            "value_type" => "variable_ref",
            "value_sheet" => ctx.sheet2.shortcut,
            "value" => ctx.quest_block.variable_name
          })

        %{
          "id" => Ecto.UUID.generate(),
          "condition" => condition,
          "instruction" => %{"assignments" => [assignment]}
        }
      end

      small_zone =
        zone_fixture(scene, %{
          "action_type" => "collection",
          "action_data" => %{"items" => [collection_item.()]},
          "condition" => condition
        })

      large_zone =
        zone_fixture(scene, %{
          "action_type" => "collection",
          "action_data" => %{"items" => for(_index <- 1..20, do: collection_item.())},
          "condition" => condition
        })

      {:ok, small_queries} =
        capture_queries(fn ->
          VariableReferenceTracker.update_scene_zone_references(
            small_zone,
            project_id: ctx.project.id
          )
        end)

      {:ok, large_queries} =
        capture_queries(fn ->
          VariableReferenceTracker.update_scene_zone_references(
            large_zone,
            project_id: ctx.project.id
          )
        end)

      assert length(large_queries) == length(small_queries)

      assert large_zone.id
             |> scene_zone_references()
             |> MapSet.new(&{&1.block_id, &1.kind, &1.source_sheet, &1.source_variable}) ==
               MapSet.new([
                 {ctx.health_block.id, "read", ctx.sheet.shortcut, ctx.health_block.variable_name},
                 {ctx.health_block.id, "write", ctx.sheet.shortcut, ctx.health_block.variable_name},
                 {ctx.quest_block.id, "read", ctx.sheet2.shortcut, ctx.quest_block.variable_name}
               ])
    end
  end

  describe "resolve_block with nil/empty shortcut" do
    test "instruction with nil sheet produces no references", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => nil,
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(from(vr in VariableReference, where: vr.flow_node_id == ^node.id))

      assert refs == []
    end

    test "instruction with empty string variable produces no references", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(from(vr in VariableReference, where: vr.flow_node_id == ^node.id))

      assert refs == []
    end
  end

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

  defp source_identities(block_id) do
    VariableReference
    |> where([reference], reference.block_id == ^block_id)
    |> Repo.all()
    |> MapSet.new(&{&1.source_type, &1.source_id})
  end

  defp reinsert_block(block) do
    attrs =
      Map.take(block, [
        :type,
        :position,
        :config,
        :value,
        :word_count,
        :is_constant,
        :variable_name,
        :scope,
        :inherited_from_block_id,
        :detached,
        :required,
        :column_group_id,
        :column_index
      ])

    %Block{id: block.id, sheet_id: block.sheet_id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp capture_queries(fun) when is_function(fun, 0) do
    handler_id = "variable-reference-tracker-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp scene_zone_references(zone_id) do
    Repo.all(
      from(reference in VariableReference,
        where:
          reference.source_type == "scene_zone" and
            reference.source_id == ^zone_id
      )
    )
  end
end
