defmodule Storyarn.Projects.References.PortableProjectSnapshotVariableTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.References.PortableVariableSnapshot

  test "rewrites only authoritative shortcutless variable surfaces" do
    old_namespace = "10"
    new_namespace = "99"
    shadow_instruction = Jason.encode!([assignment(old_namespace, "hp")])

    structured_response = %{
      "condition" => Jason.encode!(condition(old_namespace, "hp")),
      "instruction_assignments" => [
        old_namespace
        |> assignment("hp")
        |> Map.put("value_sheet", old_namespace)
      ],
      "instruction" => shadow_instruction,
      "metadata" => %{"sheet" => old_namespace, "variable_ref" => "#{old_namespace}.hp"}
    }

    legacy_response = %{
      "condition" => Jason.encode!(condition(old_namespace, "hp")),
      "instruction_assignments" => [],
      "instruction" => Jason.encode!([assignment(old_namespace, "hp")])
    }

    literal_data = %{
      "metadata" => %{
        "sheet" => old_namespace,
        "value_sheet" => old_namespace,
        "variable_ref" => "#{old_namespace}.hp"
      }
    }

    snapshot =
      project_snapshot(
        [
          sheet_entry(10, nil, [
            regular_block(100, "hp"),
            formula_table_block(101, "#{old_namespace}.hp")
          ])
        ],
        [
          %{
            "original_id" => 200,
            "type" => "dialogue",
            "data" => %{
              "responses" => [structured_response, legacy_response],
              "metadata" => literal_data
            }
          },
          %{"original_id" => 201, "type" => "annotation", "data" => literal_data}
        ]
      )

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:ok, rewritten} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(
               snapshot,
               plan,
               %{10 => 99}
             )

    [rewritten_sheet] = rewritten["sheets"]

    formula =
      get_in(rewritten_sheet, [
        "snapshot",
        "blocks",
        Access.at(1),
        "table_data",
        "rows",
        Access.at(0),
        "cells",
        "computed"
      ])

    assert formula["bindings"]["source"]["ref"] == "#{new_namespace}.hp"

    [dialogue, annotation] = get_in(rewritten, ["flows", Access.at(0), "snapshot", "nodes"])
    [structured, legacy] = dialogue["data"]["responses"]

    assert condition_sheet(Jason.decode!(structured["condition"])) == new_namespace
    assert hd(structured["instruction_assignments"])["sheet"] == new_namespace
    assert hd(structured["instruction_assignments"])["value_sheet"] == old_namespace
    assert structured["instruction"] == shadow_instruction
    assert structured["metadata"] == structured_response["metadata"]

    assert condition_sheet(Jason.decode!(legacy["condition"])) == new_namespace
    assert hd(Jason.decode!(legacy["instruction"]))["sheet"] == new_namespace
    assert dialogue["data"]["metadata"] == literal_data
    assert annotation["data"] == literal_data
  end

  test "rejects a dangling formula variable before rewrite" do
    snapshot =
      project_snapshot([
        sheet_entry(10, nil, [
          regular_block(100, "hp"),
          formula_table_block(101, "10.missing")
        ])
      ])

    assert {:error, {:unresolved_variable_reference, "table_formula", 1002, "read", "10", "missing"}} =
             PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
  end

  test "rejects malformed same-row bindings and bindings absent from the expression" do
    valid_variable = %{
      "type" => "variable",
      "ref" => "10.hp"
    }

    invalid_cells = [
      %{
        "expression" => "source",
        "bindings" => %{
          "source" => %{"type" => "same_row", "column_slug" => "computed"}
        }
      },
      %{
        "expression" => "source",
        "bindings" => %{"source" => valid_variable, "extra" => valid_variable}
      }
    ]

    for invalid_cell <- invalid_cells do
      snapshot =
        project_snapshot([
          sheet_entry(10, nil, [
            regular_block(100, "hp"),
            formula_table_block(101, "10.hp", invalid_cell)
          ])
        ])

      assert {:error, {:invalid_portable_formula_cell, 101, 1002, "computed", ^invalid_cell}} =
               PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
    end
  end

  test "accepts recoverable unhealthy formulas produced by the live writer" do
    unhealthy_cells = [
      %{"expression" => "orphan * 2", "bindings" => %{}},
      %{"expression" => "1 +", "bindings" => %{}}
    ]

    for unhealthy_cell <- unhealthy_cells do
      snapshot =
        project_snapshot([
          sheet_entry(10, nil, [
            formula_table_block(101, "unused", unhealthy_cell)
          ])
        ])

      assert {:ok, _plan} =
               PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
    end
  end

  test "rejects table cells whose column is absent from the snapshot schema" do
    block = formula_table_block(101, "10.hp")

    block =
      update_in(block, ["table_data", "rows", Access.at(0), "cells"], fn cells ->
        Map.put(cells, "ghost", "untyped")
      end)

    snapshot =
      project_snapshot([
        sheet_entry(10, nil, [regular_block(100, "hp"), block])
      ])

    assert {:error, {:invalid_portable_table_cell_key, 101, 1002, "ghost"}} =
             PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
  end

  test "preserves noncanonical legacy JSON when fixed-shortcut references do not change" do
    condition_json =
      ~s({ "logic" : "all", "blocks" : [{"type":"block","rules":[{"sheet":"actors","variable":"hp","operator":"greater_than"}]}] })

    instruction_json =
      ~s([ { "sheet" : "actors", "variable" : "hp", "operator" : "set", "value_type" : "literal", "value" : "1" } ])

    snapshot =
      project_snapshot(
        [sheet_entry(10, "actors", [regular_block(100, "hp")])],
        [
          %{
            "original_id" => 200,
            "type" => "dialogue",
            "data" => %{
              "responses" => [
                %{
                  "condition" => condition_json,
                  "instruction_assignments" => [],
                  "instruction" => instruction_json
                }
              ]
            }
          }
        ]
      )

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:ok, rewritten} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(
               snapshot,
               plan,
               %{10 => 99}
             )

    [response] = get_in(rewritten, ["flows", Access.at(0), "snapshot", "nodes", Access.at(0), "data", "responses"])
    assert response["condition"] == condition_json
    assert response["instruction"] == instruction_json
  end

  test "explicit numeric shortcuts own source namespaces before definitions are cataloged" do
    entries = [
      sheet_entry(42, nil, [regular_block(100, "hp")]),
      sheet_entry(84, "42", [regular_block(200, "mana")])
    ]

    for sheets <- [entries, Enum.reverse(entries)] do
      snapshot = project_snapshot(sheets)

      assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
      assert plan.sheet_ids == MapSet.new([42, 84])
      assert plan.namespace_owners == %{"42" => 84}
      assert plan.rewritable_namespaces == %{}
      assert Map.keys(plan.qualified_targets) == ["42.mana"]
      assert plan.rewritable_qualified_targets == %{}
    end
  end

  test "rejects references to a fallback shadowed by a variable-free explicit shortcut" do
    snapshot =
      project_snapshot(
        [
          sheet_entry(42, nil, [regular_block(100, "hp")]),
          sheet_entry(84, "42", [])
        ],
        [
          %{
            "original_id" => 200,
            "type" => "condition",
            "data" => %{"condition" => condition("42", "hp")}
          }
        ]
      )

    assert {:error, {:unresolved_variable_reference, "flow_node", 200, "read", "42", "hp"}} =
             PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)
  end

  test "rejects destination numeric namespaces that collide with fixed shortcuts" do
    snapshot =
      project_snapshot([
        sheet_entry(10, nil, [regular_block(100, "hp")]),
        sheet_entry(20, "42", [regular_block(200, "mana")])
      ])

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:error, {:ambiguous_destination_variable_namespace, "42", 10, 20}} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(
               snapshot,
               plan,
               %{10 => 42, 20 => 43}
             )
  end

  test "exact restore remaps valid namespaces without validating unresolved references" do
    snapshot =
      project_snapshot(
        [sheet_entry(10, nil, [regular_block(100, "hp")])],
        [
          %{
            "original_id" => 200,
            "type" => "condition",
            "data" => %{"condition" => condition("10", "missing")}
          }
        ]
      )

    assert {:ok, plan} = PortableVariableSnapshot.prepare_exact_project_snapshot(snapshot)

    assert {:ok, rewritten} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(snapshot, plan, %{10 => 42})

    [flow] = rewritten["flows"]
    [node] = flow["snapshot"]["nodes"]

    assert get_in(node, ["data", "condition", "blocks", Access.at(0), "rules", Access.at(0), "sheet"]) == "42"
  end

  test "rejects a non-injective destination sheet mapping" do
    snapshot =
      project_snapshot([
        sheet_entry(10, nil, [regular_block(100, "hp")]),
        sheet_entry(20, "actors", [regular_block(200, "mana")])
      ])

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:error, {:non_injective_portable_variable_sheet_mapping, %{10 => 42, 20 => 42}}} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(
               snapshot,
               plan,
               %{10 => 42, 20 => 42}
             )
  end

  test "does not reject a destination namespace collision between variable-free sheets" do
    snapshot =
      project_snapshot([
        sheet_entry(10, nil, []),
        sheet_entry(20, "42", [])
      ])

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:ok, ^snapshot} =
             PortableVariableSnapshot.rewrite_portable_project_snapshot(
               snapshot,
               plan,
               %{10 => 42, 20 => 43}
             )
  end

  test "bounds local materialization retries by fixed numeric variable namespaces only" do
    snapshot =
      project_snapshot([
        sheet_entry(10, nil, [regular_block(100, "hp")]),
        sheet_entry(20, "42", [regular_block(200, "mana")]),
        sheet_entry(30, "actors", [regular_block(300, "level")]),
        sheet_entry(40, "99999999999999999999999999999999999999", [regular_block(400, "luck")]),
        sheet_entry(50, "77", [])
      ])

    assert {:ok, plan} = PortableVariableSnapshot.prepare_portable_project_snapshot(snapshot)

    assert {:ok, 2} =
             PortableVariableSnapshot.portable_namespace_materialization_attempt_limit(plan)
  end

  defp project_snapshot(sheets, nodes \\ []) do
    flows =
      if nodes == [] do
        []
      else
        [%{"id" => 300, "snapshot" => %{"nodes" => nodes}}]
      end

    %{"sheets" => sheets, "flows" => flows, "scenes" => []}
  end

  defp sheet_entry(id, shortcut, blocks) do
    %{
      "id" => id,
      "snapshot" => %{
        "original_id" => id,
        "shortcut" => shortcut,
        "blocks" => blocks
      }
    }
  end

  defp regular_block(id, variable_name) do
    %{
      "original_id" => id,
      "type" => "number",
      "is_constant" => false,
      "variable_name" => variable_name
    }
  end

  defp formula_table_block(id, qualified_ref, cell \\ nil) do
    cell =
      cell ||
        %{
          "expression" => "source",
          "bindings" => %{
            "source" => %{"type" => "variable", "ref" => qualified_ref}
          }
        }

    %{
      "original_id" => id,
      "type" => "table",
      "variable_name" => "stats",
      "table_data" => %{
        "columns" => [
          %{"slug" => "computed", "type" => "formula", "is_constant" => false}
        ],
        "rows" => [
          %{
            "original_id" => 1002,
            "slug" => "hero",
            "cells" => %{
              "computed" => cell
            }
          }
        ]
      }
    }
  end

  defp assignment(sheet, variable) do
    %{
      "sheet" => sheet,
      "variable" => variable,
      "operator" => "set",
      "value" => "1",
      "value_type" => "literal"
    }
  end

  defp condition(sheet, variable) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "condition-block",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "condition-rule",
              "sheet" => sheet,
              "variable" => variable,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end

  defp condition_sheet(condition) do
    get_in(condition, ["blocks", Access.at(0), "rules", Access.at(0), "sheet"])
  end
end
