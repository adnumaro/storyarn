defmodule Storyarn.Flows.VariableReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.References
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneZone
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

  describe "delete_references/1" do
    test "removes all references for a node", ctx do
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

      VariableReferenceTracker.delete_references(node.id)
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

  describe "get_variable_usage/2" do
    test "returns reads and writes with flow info", ctx do
      instruction_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "add",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      condition_node =
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

      VariableReferenceTracker.update_references(instruction_node)
      VariableReferenceTracker.update_references(condition_node)

      usage = VariableReferenceTracker.get_variable_usage(ctx.health_block.id, ctx.project.id)
      assert length(usage) == 2

      reads = Enum.filter(usage, &(&1.kind == "read"))
      writes = Enum.filter(usage, &(&1.kind == "write"))

      assert length(reads) == 1
      assert length(writes) == 1

      read = hd(reads)
      assert read.node_id == condition_node.id
      assert read.node_type == "condition"
      assert read.flow_id == ctx.flow.id

      write = hd(writes)
      assert write.node_id == instruction_node.id
      assert write.node_type == "instruction"
    end

    test "excludes references from deleted flows", ctx do
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

      # Soft-delete the flow
      Flows.delete_flow(ctx.flow)

      usage = VariableReferenceTracker.get_variable_usage(ctx.health_block.id, ctx.project.id)
      assert usage == []
    end
  end

  describe "count_variable_usage/1" do
    test "returns grouped counts", ctx do
      instruction_node =
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

      condition_node =
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

      VariableReferenceTracker.update_references(instruction_node)
      VariableReferenceTracker.update_references(condition_node)

      counts = VariableReferenceTracker.count_variable_usage(ctx.health_block.id)
      assert counts["write"] == 1
      assert counts["read"] == 1
    end

    test "returns empty map for unused variable", ctx do
      counts = VariableReferenceTracker.count_variable_usage(ctx.health_block.id)
      assert counts == %{}
    end
  end

  describe "check_stale_references/2" do
    test "returns stale: false when node JSON matches current names", ctx do
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

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == false
    end

    test "returns stale: true when sheet shortcut was renamed", ctx do
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

      # Rename the sheet shortcut (simulating what happens in the UI)
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end

    test "counts stale references for multiple blocks in one batch", ctx do
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      assert VariableReferenceTracker.count_stale_references(
               [ctx.health_block.id, -1],
               ctx.project.id
             ) == %{ctx.health_block.id => 1}
    end

    test "detects stale condition read ref after rename", ctx do
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

      # Rename the sheet shortcut
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end

    test "returns empty list for nonexistent block", ctx do
      refs = VariableReferenceTracker.check_stale_references(-1, ctx.project.id)
      assert refs == []
    end

    test "returns empty list when sheet is soft-deleted", ctx do
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

      # Soft-delete the sheet
      Storyarn.Sheets.delete_sheet(ctx.sheet)

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert refs == []
    end

    test "returns empty list when block is soft-deleted", ctx do
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

      # Soft-delete the block
      Storyarn.Sheets.delete_block(ctx.health_block)

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert refs == []
    end
  end

  describe "repair_stale_references/1" do
    test "repairs stale instruction write ref after sheet rename", ctx do
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

      # Rename the sheet shortcut
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      # Verify it's stale
      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert hd(refs).stale == true

      # Repair
      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      # Verify no longer stale
      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == false

      # Verify node data was updated
      updated_node = Storyarn.Repo.get!(FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["sheet"] == "mc.renamed"
      assert assignment["variable"] == "health"
    end

    test "repairs stale condition read ref after sheet rename", ctx do
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

      # Rename the sheet shortcut
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      # Verify node data was updated
      updated_node = Storyarn.Repo.get!(FlowNode, node.id)
      rule = hd(hd(updated_node.data["condition"]["blocks"])["rules"])
      assert rule["sheet"] == "mc.renamed"
      assert rule["variable"] == "health"
    end

    test "repairs every stale dialogue response variable surface without changing response shapes", ctx do
      legacy_block =
        block_fixture(ctx.sheet2, %{
          type: "number",
          config: %{"label" => "Legacy Count", "placeholder" => "0"}
        })

      condition =
        ctx.sheet.shortcut
        |> variable_condition(ctx.health_block.variable_name)
        |> update_in(["blocks", Access.at(0), "rules"], &(&1 ++ ["condition draft"]))

      structured_assignment =
        ctx.sheet2.shortcut
        |> variable_assignment(ctx.quest_block.variable_name)
        |> Map.merge(%{
          "value_type" => "variable_ref",
          "value_sheet" => ctx.sheet.shortcut,
          "value" => ctx.health_block.variable_name
        })

      legacy_assignment =
        variable_assignment(ctx.sheet2.shortcut, legacy_block.variable_name)

      untouched_response = %{
        "id" => "draft",
        "text" => "Not configured",
        "condition" => "",
        "instruction_assignments" => [],
        "instruction" => ""
      }

      node =
        node_fixture(ctx.flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{
                "id" => "structured",
                "text" => "Structured",
                "condition" => Jason.encode!(condition),
                "instruction_assignments" => [structured_assignment, "assignment draft"]
              },
              %{
                "id" => "legacy",
                "text" => "Legacy",
                "condition" => nil,
                "instruction_assignments" => [],
                "instruction" => Jason.encode!([legacy_assignment, 17])
              },
              %{
                "id" => "map-condition",
                "text" => "Map condition",
                "condition" => condition,
                "instruction_assignments" => []
              },
              untouched_response
            ]
          }
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet2, %{shortcut: "global.renamed"})

      Repo.update!(Ecto.Changeset.change(ctx.health_block, variable_name: "vitality"))
      Repo.update!(Ecto.Changeset.change(ctx.quest_block, variable_name: "quest_complete"))
      Repo.update!(Ecto.Changeset.change(legacy_block, variable_name: "legacy_total"))

      assert {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)

      updated_node = Repo.get!(FlowNode, node.id)

      [structured_response, legacy_response, map_response, draft_response] =
        updated_node.data["responses"]

      assert Enum.map(updated_node.data["responses"], & &1["id"]) ==
               ~w(structured legacy map-condition draft)

      assert is_binary(structured_response["condition"])

      [repaired_rule, condition_draft] =
        structured_response["condition"]
        |> Jason.decode!()
        |> then(&hd(&1["blocks"])["rules"])

      assert repaired_rule["sheet"] == "mc.renamed"
      assert repaired_rule["variable"] == "vitality"
      assert condition_draft == "condition draft"

      [repaired_structured_assignment, assignment_draft] =
        structured_response["instruction_assignments"]

      assert repaired_structured_assignment["sheet"] == "global.renamed"
      assert repaired_structured_assignment["variable"] == "quest_complete"
      assert repaired_structured_assignment["value_sheet"] == "mc.renamed"
      assert repaired_structured_assignment["value"] == "vitality"
      assert assignment_draft == "assignment draft"

      assert legacy_response["instruction_assignments"] == []
      assert is_binary(legacy_response["instruction"])

      [repaired_legacy_assignment, legacy_draft] =
        Jason.decode!(legacy_response["instruction"])

      assert repaired_legacy_assignment["sheet"] == "global.renamed"
      assert repaired_legacy_assignment["variable"] == "legacy_total"
      assert legacy_draft == 17

      assert is_map(map_response["condition"])
      [repaired_map_rule, map_condition_draft] = hd(map_response["condition"]["blocks"])["rules"]
      assert repaired_map_rule["sheet"] == "mc.renamed"
      assert repaired_map_rule["variable"] == "vitality"
      assert map_condition_draft == "condition draft"
      assert draft_response == untouched_response

      assert {:ok, 0} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
    end

    test "returns 0 when nothing is stale", ctx do
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

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 0
    end

    test "broadcasts one dashboard invalidation after repairing multiple nodes", ctx do
      nodes =
        for _index <- 1..2 do
          node =
            node_fixture(ctx.flow, %{
              type: "instruction",
              data: %{
                "assignments" => [
                  variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)
                ]
              }
            })

          :ok = VariableReferenceTracker.update_references(node)
          node
        end

      {:ok, _sheet} = Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})
      :ok = Collaboration.subscribe_dashboard(ctx.project.id)

      assert {:ok, 2} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10

      assert Enum.all?(nodes, fn node ->
               updated_node = Storyarn.Repo.get!(FlowNode, node.id)
               assignment = hd(updated_node.data["assignments"])
               assignment["sheet"] == "mc.renamed"
             end)
    end

    test "does not broadcast when the repair is a no-op", ctx do
      :ok = Collaboration.subscribe_dashboard(ctx.project.id)

      assert {:ok, 0} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      refute_receive {:dashboard_invalidate, :flows}, 10
    end

    test "keeps successful repairs when a later node cannot be repaired", ctx do
      valid_assignment =
        variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)

      valid_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{"assignments" => [valid_assignment]}
        })

      failing_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{"assignments" => [valid_assignment]}
        })

      :ok = VariableReferenceTracker.update_references(valid_node)
      :ok = VariableReferenceTracker.update_references(failing_node)

      # Keep the tracked reference deliberately while making the node
      # unwritable. The repair query still sees the reference, but one damaged
      # source must not roll back every independent repair in the project.
      failing_node
      |> FlowNode.soft_delete_changeset()
      |> Storyarn.Repo.update!()

      {:ok, _sheet} = Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})
      :ok = Collaboration.subscribe_dashboard(ctx.project.id)

      assert {:error, {:partial_variable_reference_repair, %{repaired_count: 1, failures: [{failing_id, _reason}]}}} =
               VariableReferenceTracker.repair_stale_references(ctx.project.id)

      assert failing_id == failing_node.id
      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10

      persisted_valid = Storyarn.Repo.get!(FlowNode, valid_node.id)
      persisted_failing = Storyarn.Repo.get!(FlowNode, failing_node.id)

      assert hd(persisted_valid.data["assignments"])["sheet"] == "mc.renamed"
      assert persisted_failing.data == failing_node.data
      assert persisted_failing.deleted_at
    end
  end

  describe "list_stale_node_ids/1" do
    test "returns node IDs with stale references", ctx do
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

      # Not stale yet
      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0

      # Rename sheet
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "returns empty MapSet when no stale refs exist", ctx do
      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0
    end

    test "returns only stale node IDs when mixed stale and non-stale nodes exist", ctx do
      stale_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      fresh_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a2",
                "sheet" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set_true",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(stale_node)
      VariableReferenceTracker.update_references(fresh_node)

      # Rename only mc.jaime → mc.renamed
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, stale_node.id)
      refute MapSet.member?(stale_ids, fresh_node.id)
    end

    test "excludes nodes referencing soft-deleted sheets", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Soft-delete the sheet — should NOT show as stale
      Storyarn.Sheets.delete_sheet(ctx.sheet)

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0
    end
  end

  describe "repair_stale_references/1 — deterministic matching" do
    test "multi-assignment repair: only stale assignment is updated", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "sheet" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set_true",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename only mc.jaime → mc.renamed
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      assert a1["sheet"] == "mc.renamed"
      assert a1["variable"] == "health"
      # Second assignment must be untouched
      assert a2["sheet"] == "global.quests"
      assert a2["variable"] == "sword_done"
    end

    test "variable_ref source repair after sheet rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set",
                "value" => "health",
                "value_type" => "variable_ref",
                "value_sheet" => "mc.jaime"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the source sheet
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])

      assert assignment["value_sheet"] == "mc.renamed"
      assert assignment["value"] == "health"
      # Write target was not stale, must be unchanged
      assert assignment["sheet"] == "global.quests"
      assert assignment["variable"] == "sword_done"
    end

    test "multi-rule condition repair: only stale rule is updated", ctx do
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
                      "id" => "r1",
                      "sheet" => "mc.jaime",
                      "variable" => "health",
                      "operator" => "greater_than",
                      "value" => "50"
                    },
                    %{
                      "id" => "r2",
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

      # Rename only mc.jaime → mc.renamed
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      [r1, r2] = hd(updated_node.data["condition"]["blocks"])["rules"]

      assert r1["sheet"] == "mc.renamed"
      assert r1["variable"] == "health"
      # Second rule must be untouched
      assert r2["sheet"] == "global.quests"
      assert r2["variable"] == "sword_done"
    end

    test "variable name rename is detected and repaired", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Directly rename variable_name bypassing CRUD protection
      ctx.health_block
      |> Ecto.Changeset.change(%{variable_name: "vitality"})
      |> Storyarn.Repo.update!()

      # Verify stale
      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true

      # Repair
      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["sheet"] == "mc.jaime"
      assert assignment["variable"] == "vitality"
    end

    test "mixed stale/non-stale assignments: only stale one is fixed", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "sheet" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set_true",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename only mc.jaime
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)

      updated_node = Repo.get!(FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      # Stale one repaired
      assert a1["sheet"] == "mc.renamed"
      assert a1["variable"] == "health"
      # Fresh one untouched
      assert a2["sheet"] == "global.quests"
      assert a2["variable"] == "sword_done"
    end

    test "repair is idempotent — second run returns 0", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      {:ok, 0} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
    end

    test "two assignments to two different sheets — both repaired correctly after rename", ctx do
      # Create a third sheet
      sheet3 = sheet_fixture(ctx.project, %{name: "Items", shortcut: "items"})

      gold_block =
        block_fixture(sheet3, %{
          type: "number",
          config: %{"label" => "Gold", "placeholder" => "0"}
        })

      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "sheet" => "items",
                "variable" => "gold",
                "operator" => "add",
                "value" => "50",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename BOTH sheets
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})
      Storyarn.Sheets.update_sheet(sheet3, %{shortcut: "inventory"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      # Each assignment gets the CORRECT new shortcut — no cross-wiring
      assert a1["sheet"] == "mc.renamed"
      assert a1["variable"] == "health"
      assert a2["sheet"] == "inventory"
      assert a2["variable"] == "gold"

      # Confirm gold_block ref was stored properly (prevents warnings)
      _gold_block = gold_block
    end
  end

  describe "check_stale_references/2 — instruction read refs" do
    test "detects stale instruction variable_ref source after sheet rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set",
                "value" => "health",
                "value_type" => "variable_ref",
                "value_sheet" => "mc.jaime"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the source sheet
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
      assert hd(refs).kind == "read"
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

      assert VariableReferenceTracker.flow_node_references_current_ids(
               [regular_node, table_node],
               ctx.project.id
             ) == MapSet.new([regular_node.id, table_node.id])

      other_project = project_fixture()

      assert VariableReferenceTracker.flow_node_references_current_ids(
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

      assert VariableReferenceTracker.flow_node_references_current_ids(
               [regular_node, table_node],
               ctx.project.id
             ) == MapSet.new([regular_node.id])
    end
  end

  # -- Table variable tests --

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

  describe "list_stale_node_ids with table variables" do
    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      strength_row = table_row_fixture(table_block, %{name: "Strength"})
      _value_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      Map.merge(ctx, %{
        table_block: table_block,
        strength_row: strength_row
      })
    end

    test "fresh table ref is not stale", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0
    end

    test "stale after sheet rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "stale after table block rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Directly rename variable_name bypassing CRUD protection
      ctx.table_block
      |> Ecto.Changeset.change(%{variable_name: "stats"})
      |> Storyarn.Repo.update!()

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "stale after row rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Directly rename slug bypassing CRUD protection
      ctx.strength_row
      |> Ecto.Changeset.change(%{slug: "power"})
      |> Storyarn.Repo.update!()

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "stale after column rename", ctx do
      extra_col = table_column_fixture(ctx.table_block, %{name: "Score", type: "number"})

      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "attributes.strength.score",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Directly rename slug bypassing CRUD protection
      extra_col
      |> Ecto.Changeset.change(%{slug: "points"})
      |> Storyarn.Repo.update!()

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "mixed regular + table: only stale one is flagged", ctx do
      table_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "attributes.strength.value",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      regular_node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a2",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(table_node)
      VariableReferenceTracker.update_references(regular_node)

      # Directly rename variable_name bypassing CRUD protection
      ctx.table_block
      |> Ecto.Changeset.change(%{variable_name: "stats"})
      |> Storyarn.Repo.update!()

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, table_node.id)
      refute MapSet.member?(stale_ids, regular_node.id)
    end
  end

  describe "check_stale_references with table variables" do
    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      strength_row = table_row_fixture(table_block, %{name: "Strength"})
      _value_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      Map.merge(ctx, %{
        table_block: table_block,
        strength_row: strength_row
      })
    end

    test "stale: false when fresh", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      refs = VariableReferenceTracker.check_stale_references(ctx.table_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == false
    end

    test "stale: true after table block rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Directly rename variable_name bypassing CRUD protection
      ctx.table_block
      |> Ecto.Changeset.change(%{variable_name: "stats"})
      |> Storyarn.Repo.update!()

      refs = VariableReferenceTracker.check_stale_references(ctx.table_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end
  end

  describe "repair_stale_references with table variables" do
    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Attributes"})
      strength_row = table_row_fixture(table_block, %{name: "Strength"})
      _value_column = table_column_fixture(table_block, %{name: "Value", type: "number"})

      Map.merge(ctx, %{
        table_block: table_block,
        strength_row: strength_row
      })
    end

    test "repairs table ref after sheet rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["sheet"] == "mc.renamed"
      assert assignment["variable"] == "attributes.strength.value"
    end

    test "repairs table ref after table block rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Directly rename variable_name bypassing CRUD protection
      ctx.table_block
      |> Ecto.Changeset.change(%{variable_name: "stats"})
      |> Storyarn.Repo.update!()

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["sheet"] == "mc.jaime"
      # table_name part replaced, row/col slugs preserved
      assert assignment["variable"] == "stats.strength.value"
    end

    test "repair is idempotent for table refs", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      {:ok, 0} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
    end

    test "mixed regular + table refs repaired correctly", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      # Both get sheet renamed
      assert a1["sheet"] == "mc.renamed"
      assert a1["variable"] == "health"
      assert a2["sheet"] == "mc.renamed"
      assert a2["variable"] == "attributes.strength.value"
    end

    test "repairs condition read ref with table variable after sheet rename", ctx do
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
                      "id" => "r1",
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
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      rule = hd(hd(updated_node.data["condition"]["blocks"])["rules"])
      assert rule["sheet"] == "mc.renamed"
      assert rule["variable"] == "attributes.strength.value"
    end
  end

  # ===========================================================================
  # Module 3C: Additional coverage tests
  # ===========================================================================

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

  describe "count_variable_usage/1 — coverage" do
    test "returns read and write counts grouped by kind", ctx do
      # Create instruction node with write ref
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
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

      # Create condition node with read ref
      cond_node =
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

      VariableReferenceTracker.update_references(cond_node)

      counts = VariableReferenceTracker.count_variable_usage(ctx.health_block.id)
      assert counts["write"] == 1
      assert counts["read"] == 1
    end

    test "returns empty map for block with no references", ctx do
      counts = VariableReferenceTracker.count_variable_usage(ctx.health_block.id)
      assert counts == %{}
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
                 VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "flow",
                 flow_snapshot
               )

      assert :ok =
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "scene",
                 scene_snapshot
               )

      assert :ok =
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "sheet",
                 %{}
               )

      invalid_scene_snapshot = put_in(scene_snapshot, ["layers", Access.at(0), "pins"], "not-a-list")

      assert {:error, {:invalid_variable_reference_snapshot_collection, "scene_layer", "pins", "not-a-list"}} =
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
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
          %{"type" => "hub", "data" => %{}}
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
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "flow",
                 flow_snapshot
               )

      assert :ok =
               VariableReferenceTracker.validate_entity_snapshot_variable_references(
                 ctx.project.id,
                 "scene",
                 scene_snapshot
               )
    end

    test "entity preview and restore validation reject the same malformed Flow collections", ctx do
      cases = [
        {%{
           "original_id" => 100,
           "type" => "instruction",
           "data" => %{"assignments" => nil}
         }, {:malformed_variable_reference, "flow_node", 100, :assignments, nil}},
        {%{
           "original_id" => 101,
           "type" => "dialogue",
           "data" => %{"responses" => nil}
         }, {:malformed_variable_reference, "flow_node", 101, :dialogue_responses, nil}}
      ]

      for {node, reason} <- cases do
        assert {:error, ^reason} =
                 VariableReferenceTracker.validate_flow_node_variable_targets(
                   [node],
                   ctx.project.id
                 )

        assert {:error, ^reason} =
                 VariableReferenceTracker.validate_entity_snapshot_variable_references(
                   ctx.project.id,
                   "flow",
                   %{"nodes" => [node]}
                 )
      end
    end

    test "entity preview and restore validation reject the same malformed Scene action collections", ctx do
      cases = [
        {%{
           "original_id" => 102,
           "action_type" => "action",
           "action_data" => %{"assignments" => nil},
           "condition" => nil
         }, {:malformed_variable_reference, "scene_zone", 102, :assignments, nil}},
        {%{
           "original_id" => 103,
           "action_type" => "collection",
           "action_data" => %{"items" => nil},
           "condition" => nil
         }, {:malformed_variable_reference, "scene_zone", 103, :collection_items, nil}}
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
                 VariableReferenceTracker.validate_snapshot_variable_references(
                   ctx.project.id,
                   [restore_source]
                 )

        assert {:error, ^reason} =
                 VariableReferenceTracker.validate_entity_snapshot_variable_references(
                   ctx.project.id,
                   "scene",
                   %{
                     "layers" => [%{"pins" => [], "zones" => [zone]}],
                     "orphan_pins" => [],
                     "orphan_zones" => [],
                     "ambient_flows" => []
                   }
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
                 VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
                 ctx.project.id,
                 [unresolved]
               )

      assert source_sheet == ctx.sheet.shortcut

      malformed =
        put_in(valid_source, [:data, "assignments", Access.at(0), "value_sheet"], nil)

      assert {:error, {:malformed_variable_reference, "flow_node", 91, :assignment_value, {nil, source_variable}}} =
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
                 ctx.project.id,
                 [source]
               )

      invalid = put_in(source, [:action_data, "assignments", Access.at(0), "variable"], "gone")

      assert {:error, {:unresolved_variable_reference, "scene_zone", 92, "write", source_sheet, "gone"}} =
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
                 VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
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
                 VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
                 ctx.project.id,
                 sources
               )

      invalid = put_in(hd(sources), [:action_data, "variable_ref"], "#{ctx.sheet.shortcut}.missing")

      assert {:error, {:unresolved_variable_reference, "scene_zone", 93, "read", "mc.jaime", "missing"}} =
               VariableReferenceTracker.validate_snapshot_variable_references(
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
               VariableReferenceTracker.validate_snapshot_variable_references(
                 ctx.project.id,
                 sources
               )
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
               VariableReferenceTracker.get_variable_usage(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert ambient_flow_id == ambient_flow.id

      assert [%{source_type: "scene_ambient_flow", stale: false}] =
               VariableReferenceTracker.check_stale_references(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.jaime.renamed"})

      assert [%{source_type: "scene_ambient_flow", stale: true}] =
               VariableReferenceTracker.check_stale_references(
                 ctx.health_block.id,
                 ctx.project.id
               )

      assert VariableReferenceTracker.count_stale_references(
               [ctx.health_block.id],
               ctx.project.id
             ) == %{ctx.health_block.id => 1}

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.jaime"})

      assert :ok = VariableReferenceTracker.delete_scene_ambient_flow_references(ambient_flow.id)

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
end
