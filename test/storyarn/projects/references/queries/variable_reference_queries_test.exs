defmodule Storyarn.Projects.References.VariableReferenceQueriesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.References.VariableReferenceQueries
  alias Storyarn.Projects.References.VariableReferenceTracker

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

      usage = VariableReferenceQueries.get_variable_usage(ctx.health_block.id, ctx.project.id)
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

      usage = VariableReferenceQueries.get_variable_usage(ctx.health_block.id, ctx.project.id)
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

      counts = VariableReferenceQueries.count_variable_usage(ctx.health_block.id)
      assert counts["write"] == 1
      assert counts["read"] == 1
    end

    test "returns empty map for unused variable", ctx do
      counts = VariableReferenceQueries.count_variable_usage(ctx.health_block.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
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

      assert VariableReferenceQueries.count_stale_references(
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end

    test "returns empty list for nonexistent block", ctx do
      refs = VariableReferenceQueries.check_stale_references(-1, ctx.project.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert refs == []
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
      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0

      # Rename sheet
      Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, node.id)
    end

    test "returns empty MapSet when no stale refs exist", ctx do
      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
      assert MapSet.size(stale_ids) == 0
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

      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
      assert hd(refs).kind == "read"
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      stale_ids = VariableReferenceQueries.list_stale_node_ids(ctx.flow.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.table_block.id, ctx.project.id)
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

      refs = VariableReferenceQueries.check_stale_references(ctx.table_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
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

      counts = VariableReferenceQueries.count_variable_usage(ctx.health_block.id)
      assert counts["write"] == 1
      assert counts["read"] == 1
    end

    test "returns empty map for block with no references", ctx do
      counts = VariableReferenceQueries.count_variable_usage(ctx.health_block.id)
      assert counts == %{}
    end
  end
end
