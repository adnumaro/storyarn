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
end
