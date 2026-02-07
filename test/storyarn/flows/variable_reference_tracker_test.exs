defmodule Storyarn.Flows.VariableReferenceTrackerTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.PagesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.{VariableReference, VariableReferenceTracker}

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    # Create a page with shortcut "mc.jaime" and a number variable "health"
    page =
      page_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

    health_block =
      block_fixture(page, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    # Create a second page for variable_ref testing
    page2 =
      page_fixture(project, %{name: "Global Quests", shortcut: "global.quests"})

    quest_block =
      block_fixture(page2, %{
        type: "boolean",
        config: %{"label" => "Sword Done"}
      })

    %{
      project: project,
      flow: flow,
      page: page,
      health_block: health_block,
      page2: page2,
      quest_block: quest_block
    }
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
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "sword_done",
                "value_type" => "variable_ref",
                "value_page" => "global.quests"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference) |> Enum.sort_by(& &1.kind)
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
                "page" => "nonexistent.page",
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "nonexistent_var",
                "value_type" => "variable_ref",
                "value_page" => "nonexistent.page"
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

    test "stores source_page and source_variable on write reference", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
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
      assert ref.source_page == "mc.jaime"
      assert ref.source_variable == "health"
    end

    test "stores source_page and source_variable on read reference from variable_ref", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "sword_done",
                "value_type" => "variable_ref",
                "value_page" => "global.quests"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      read_ref = Repo.all(VariableReference) |> Enum.find(&(&1.kind == "read"))
      assert read_ref.source_page == "global.quests"
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
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
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
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                },
                %{
                  "id" => "rule_2",
                  "page" => "global.quests",
                  "variable" => "sword_done",
                  "operator" => "is_true",
                  "value" => nil
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      refs = Repo.all(VariableReference)
      assert length(refs) == 2
      assert Enum.all?(refs, &(&1.kind == "read"))

      block_ids = Enum.map(refs, & &1.block_id) |> Enum.sort()
      expected = Enum.sort([ctx.health_block.id, ctx.quest_block.id])
      assert block_ids == expected
    end

    test "stores source_page and source_variable on condition read reference", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      ref = Repo.one!(VariableReference)
      assert ref.source_page == "mc.jaime"
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
                "page" => "mc.jaime",
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
              "page" => "global.quests",
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
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
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
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
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
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
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
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
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
                "page" => "mc.jaime",
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

    test "returns stale: true when page shortcut was renamed", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the page shortcut (simulating what happens in the UI)
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end

    test "detects stale condition read ref after rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the page shortcut
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
    end

    test "returns empty list for nonexistent block", ctx do
      refs = VariableReferenceTracker.check_stale_references(-1, ctx.project.id)
      assert refs == []
    end

    test "returns empty list when page is soft-deleted", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Soft-delete the page
      Storyarn.Pages.delete_page(ctx.page)

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
                "page" => "mc.jaime",
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
      Storyarn.Pages.delete_block(ctx.health_block)

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert refs == []
    end
  end

  describe "repair_stale_references/1" do
    test "repairs stale instruction write ref after page rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the page shortcut
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

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
      updated_node = Storyarn.Repo.get!(Storyarn.Flows.FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["page"] == "mc.renamed"
      assert assignment["variable"] == "health"
    end

    test "repairs stale condition read ref after page rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "rule_1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the page shortcut
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      # Verify node data was updated
      updated_node = Storyarn.Repo.get!(Storyarn.Flows.FlowNode, node.id)
      rule = hd(updated_node.data["condition"]["rules"])
      assert rule["page"] == "mc.renamed"
      assert rule["variable"] == "health"
    end

    test "returns 0 when nothing is stale", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "page" => "mc.jaime",
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
                "page" => "mc.jaime",
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

      # Rename page
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

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
                "page" => "mc.jaime",
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
                "page" => "global.quests",
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
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      stale_ids = VariableReferenceTracker.list_stale_node_ids(ctx.flow.id)
      assert MapSet.member?(stale_ids, stale_node.id)
      refute MapSet.member?(stale_ids, fresh_node.id)
    end

    test "excludes nodes referencing soft-deleted pages", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Soft-delete the page — should NOT show as stale
      Storyarn.Pages.delete_page(ctx.page)

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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "page" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set_true",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename only mc.jaime → mc.renamed
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      assert a1["page"] == "mc.renamed"
      assert a1["variable"] == "health"
      # Second assignment must be untouched
      assert a2["page"] == "global.quests"
      assert a2["variable"] == "sword_done"
    end

    test "variable_ref source repair after page rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "page" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set",
                "value" => "health",
                "value_type" => "variable_ref",
                "value_page" => "mc.jaime"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the source page
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])

      assert assignment["value_page"] == "mc.renamed"
      assert assignment["value"] == "health"
      # Write target was not stale, must be unchanged
      assert assignment["page"] == "global.quests"
      assert assignment["variable"] == "sword_done"
    end

    test "multi-rule condition repair: only stale rule is updated", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "r1",
                  "page" => "mc.jaime",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                },
                %{
                  "id" => "r2",
                  "page" => "global.quests",
                  "variable" => "sword_done",
                  "operator" => "is_true",
                  "value" => nil
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename only mc.jaime → mc.renamed
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      [r1, r2] = updated_node.data["condition"]["rules"]

      assert r1["page"] == "mc.renamed"
      assert r1["variable"] == "health"
      # Second rule must be untouched
      assert r2["page"] == "global.quests"
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the block's variable_name (label change: "Health" → "Vitality")
      Storyarn.Pages.update_block(ctx.health_block, %{
        config: %{"label" => "Vitality", "placeholder" => "0"}
      })

      # Verify stale
      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true

      # Repair
      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      assignment = hd(updated_node.data["assignments"])
      assert assignment["page"] == "mc.jaime"
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "page" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set_true",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename only mc.jaime
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      # Stale one repaired
      assert a1["page"] == "mc.renamed"
      assert a1["variable"] == "health"
      # Fresh one untouched
      assert a2["page"] == "global.quests"
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      {:ok, 1} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      {:ok, 0} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
    end

    test "two assignments to two different pages — both repaired correctly after rename", ctx do
      # Create a third page
      page3 = page_fixture(ctx.project, %{name: "Items", shortcut: "items"})

      gold_block =
        block_fixture(page3, %{
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
                "page" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              },
              %{
                "id" => "a2",
                "page" => "items",
                "variable" => "gold",
                "operator" => "add",
                "value" => "50",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename BOTH pages
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})
      Storyarn.Pages.update_page(page3, %{shortcut: "inventory"})

      {:ok, count} = VariableReferenceTracker.repair_stale_references(ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(Storyarn.Flows.FlowNode, node.id)
      [a1, a2] = updated_node.data["assignments"]

      # Each assignment gets the CORRECT new shortcut — no cross-wiring
      assert a1["page"] == "mc.renamed"
      assert a1["variable"] == "health"
      assert a2["page"] == "inventory"
      assert a2["variable"] == "gold"

      # Confirm gold_block ref was stored properly (prevents warnings)
      _gold_block = gold_block
    end
  end

  describe "check_stale_references/2 — instruction read refs" do
    test "detects stale instruction variable_ref source after page rename", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "page" => "global.quests",
                "variable" => "sword_done",
                "operator" => "set",
                "value" => "health",
                "value_type" => "variable_ref",
                "value_page" => "mc.jaime"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Rename the source page
      Storyarn.Pages.update_page(ctx.page, %{shortcut: "mc.renamed"})

      refs = VariableReferenceTracker.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true
      assert hd(refs).kind == "read"
    end
  end
end
