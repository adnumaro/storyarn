defmodule Storyarn.Projects.References.VariableUsageTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Projects.Persistence.LocalizedTextRecord
  alias Storyarn.Projects.References.Persistence.FlowNodeRecord, as: FlowNode
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

  describe "repair_stale_references/1" do
    test "preserves the Projects public maintenance workflow through the Flow-owned writer", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)
            ]
          }
        })

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      assert {:ok, 1} =
               Projects.repair_stale_project_variable_references(ctx.scope, ctx.project.id)

      persisted = Repo.get!(FlowNode, node.id)
      assert hd(persisted.data["assignments"])["sheet"] == "mc.renamed"
      assert hd(persisted.data["assignments"])["variable"] == ctx.health_block.variable_name
    end

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
      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert hd(refs).stale == true

      # Repair
      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      assert count == 1

      # Verify no longer stale
      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      assert count == 1

      # Verify node data was updated
      updated_node = Storyarn.Repo.get!(FlowNode, node.id)
      rule = hd(hd(updated_node.data["condition"]["blocks"])["rules"])
      assert rule["sheet"] == "mc.renamed"
      assert rule["variable"] == "health"
    end

    test "repairs every stale dialogue response variable surface without changing response shapes", ctx do
      _language = language_fixture(ctx.project)

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

      assert {:ok, 1} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)

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

      localized_fields =
        LocalizedTextRecord
        |> where(
          [text],
          text.source_type == "flow_node" and text.source_id == ^node.id and
            text.locale_code == "es" and is_nil(text.archived_at)
        )
        |> order_by([text], asc: text.source_field)
        |> select([text], {text.source_field, text.source_text})
        |> Repo.all()

      assert localized_fields ==
               Enum.sort([
                 {"response.legacy.text", "Legacy"},
                 {"response.map-condition.text", "Map condition"},
                 {"response.structured.text", "Structured"},
                 {"response.draft.text", "Not configured"},
                 {"text", "Choose"}
               ])

      assert {:ok, 0} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      assert {:ok, 2} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      assert {:ok, 0} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      refute_receive {:dashboard_invalidate, :flows}, 10
    end

    test "ignores a hard-deleted Flow node without broadcasting", ctx do
      node =
        node_fixture(ctx.flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              variable_assignment(ctx.sheet.shortcut, ctx.health_block.variable_name)
            ]
          }
        })

      assert {:ok, _sheet} =
               Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

      Repo.delete!(node)
      :ok = Collaboration.subscribe_dashboard(ctx.project.id)

      assert {:ok, 0} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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
      |> Ecto.Changeset.change(deleted_at: Storyarn.Platform.Shared.TimeHelpers.now())
      |> Storyarn.Repo.update!()

      {:ok, _sheet} = Storyarn.Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})
      :ok = Collaboration.subscribe_dashboard(ctx.project.id)

      assert {:error, {:partial_variable_reference_repair, %{repaired_count: 1, failures: [{failing_id, _reason}]}}} =
               Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)

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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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
      refs = VariableReferenceQueries.check_stale_references(ctx.health_block.id, ctx.project.id)
      assert length(refs) == 1
      assert hd(refs).stale == true

      # Repair
      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, 1} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)

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

      {:ok, 1} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      {:ok, 0} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, 1} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      {:ok, 0} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
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

      {:ok, count} = Flows.repair_stale_variable_references(ctx.scope, ctx.project.id)
      assert count == 1

      updated_node = Repo.get!(FlowNode, node.id)
      rule = hd(hd(updated_node.data["condition"]["blocks"])["rules"])
      assert rule["sheet"] == "mc.renamed"
      assert rule["variable"] == "attributes.strength.value"
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
end
