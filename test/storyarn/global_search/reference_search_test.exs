defmodule Storyarn.GlobalSearch.ReferenceSearchTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Flows.FlowNode
  alias Storyarn.GlobalSearch
  alias Storyarn.References
  alias Storyarn.References.EntityReference
  alias Storyarn.References.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})
    sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
    variable = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

    %{
      user: user,
      scope: scope,
      workspace: workspace,
      project: project,
      sheet: sheet,
      variable: variable
    }
  end

  describe "current-project authorization" do
    test "a viewer can search a freshly authorized project", %{user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{workspace: workspace_fixture(owner)})
      membership_fixture(project, user, "viewer")
      scope = user_scope_fixture(user)
      sheet = sheet_fixture(project, %{name: "Visible", shortcut: "visible"})
      variable = block_fixture(sheet, %{type: "number", config: %{"label" => "Score"}})

      assert {:ok, %{items: [option]}} =
               GlobalSearch.reference_options(scope, project.id, :sheet_variables, "score")

      assert option.value == %{block_id: variable.id, qualified_ref: "visible.#{variable.variable_name}"}
      refute Map.has_key?(option.value, :project_id)
    end

    test "a valid id in a foreign project never authorizes the lookup", %{scope: scope} do
      stranger = user_fixture()
      foreign_project = project_fixture(stranger, %{workspace: workspace_fixture(stranger)})

      assert {:error, :unauthorized} =
               GlobalSearch.reference_options(scope, foreign_project.id, :sheet_variables, "")
    end

    test "the same qualified ref in another accessible project never mixes",
         %{scope: scope, user: user, workspace: workspace, project: project, variable: variable} do
      other_project = project_fixture(user, %{workspace: workspace})
      other_sheet = sheet_fixture(other_project, %{name: "Other Hero", shortcut: "hero"})
      other_variable = block_fixture(other_sheet, %{type: "number", config: %{"label" => "Health"}})

      assert {:ok, %{items: [hit]}} =
               GlobalSearch.reference_pattern(scope, project.id, "hero.#{variable.variable_name}")

      assert hit.destination.id != other_sheet.id
      assert hit.destination.id in [variable.sheet_id]
      refute hit.id =~ Integer.to_string(other_variable.id)
    end

    test "client-supplied scope identity fails closed", %{scope: scope, project: project, variable: variable} do
      params = %{
        "block_id" => variable.id,
        "qualified_ref" => "hero.#{variable.variable_name}",
        "project_id" => project.id
      }

      assert {:error, :invalid_request} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_definition",
                 params
               )
    end
  end

  describe "variables and patterns" do
    test "returns a stable definition destination without authored values",
         %{scope: scope, project: project, variable: variable, sheet: sheet} do
      assert {:ok, %{items: [hit], truncated: false}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_definition",
                 %{
                   "block_id" => variable.id,
                   "qualified_ref" => "hero.#{variable.variable_name}"
                 }
               )

      assert hit.kind == :definition
      assert hit.destination == %{type: :sheet, id: sheet.id, focus: %{type: :block, id: variable.id}}
      refute Map.has_key?(hit.meta, :value)
      refute Map.has_key?(hit.meta, :config)
    end

    test "supports exact, sheet, global exact and contains patterns",
         %{scope: scope, project: project, variable: variable} do
      qualified = "hero.#{variable.variable_name}"

      for pattern <- [
            qualified,
            "hero.?",
            "sheets.**.#{variable.variable_name}",
            "sheets.**.?eal",
            "?eal"
          ] do
        assert {:ok, %{items: items}} = GlobalSearch.reference_pattern(scope, project.id, pattern)
        assert Enum.any?(items, &(&1.label == qualified)), "missing #{pattern}"
      end
    end

    test "ILIKE wildcard characters remain literal and results are bounded",
         %{scope: scope, project: project, sheet: sheet} do
      for n <- 1..3 do
        block_fixture(sheet, %{type: "number", config: %{"label" => "Bounded #{n}"}})
      end

      assert {:ok, %{items: items, truncated: true}} =
               GlobalSearch.reference_options(
                 scope,
                 project.id,
                 :sheet_variables,
                 "bounded",
                 limit: 2
               )

      assert length(items) == 2

      assert {:error, :invalid_request} = GlobalSearch.reference_pattern(scope, project.id, "?%")
      assert {:error, :invalid_request} = GlobalSearch.reference_pattern(scope, project.id, "?\\")

      assert {:error, :invalid_request} =
               GlobalSearch.reference_options(
                 scope,
                 project.id,
                 :sheet_variables,
                 String.duplicate("a", 101)
               )
    end

    test "formula bindings are read usages and expose only cell navigation",
         %{scope: scope, project: project, variable: variable} do
      source = sheet_fixture(project, %{name: "Calculations", shortcut: "calc"})
      table = table_block_fixture(source, %{label: "Maths"})
      formula = table_column_fixture(table, %{name: "Doubled", type: "formula"})
      row = hd(table.table_rows)

      {:ok, _row} =
        Sheets.update_table_cell(row, formula.slug, %{
          "expression" => "base * 2",
          "bindings" => %{
            "base" => %{
              "type" => "variable",
              "ref" => "hero.#{variable.variable_name}"
            }
          }
        })

      assert {:ok, %{items: [hit]}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_usages",
                 %{
                   "block_id" => variable.id,
                   "qualified_ref" => "hero.#{variable.variable_name}"
                 }
               )

      assert hit.kind == :formula_read
      assert hit.meta.source_type == :table_formula

      assert hit.destination == %{
               type: :sheet,
               id: source.id,
               focus: %{
                 type: :cell,
                 block_id: table.id,
                 row_id: row.id,
                 column_id: formula.id
               }
             }

      serialized = inspect(hit)
      refute serialized =~ "expression"
      refute serialized =~ "bindings"
      refute serialized =~ "base * 2"
    end

    test "tracked writes are returned and deleted nodes are excluded",
         %{scope: scope, project: project, variable: variable} do
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => Ecto.UUID.generate(),
                "sheet" => "hero",
                "variable" => variable.variable_name,
                "operator" => "set",
                "value" => "1",
                "value_type" => "literal"
              }
            ]
          }
        })

      :ok = References.update_flow_node_variable_references(node)

      params = %{
        "block_id" => variable.id,
        "qualified_ref" => "hero.#{variable.variable_name}"
      }

      assert {:ok, %{items: [%{kind: :write, destination: %{focus: %{id: node_id}}}]}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_usages",
                 params
               )

      assert node_id == node.id

      Repo.update_all(from(candidate in FlowNode, where: candidate.id == ^node.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert {:ok, %{items: []}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_usages",
                 params
               )
    end

    test "table cells are individually scoped despite sharing a block id",
         %{scope: scope, project: project, sheet: sheet} do
      table = table_block_fixture(sheet, %{label: "Attributes"})
      row = hd(table.table_rows)
      first = hd(table.table_columns)
      second = table_column_fixture(table, %{name: "Second", type: "number"})
      flow = flow_fixture(project)
      node = node_fixture(flow)

      first_path = "#{table.variable_name}.#{row.slug}.#{first.slug}"
      second_path = "#{table.variable_name}.#{row.slug}.#{second.slug}"

      first_reference =
        Repo.insert!(%VariableReference{
          source_type: "flow_node",
          source_id: node.id,
          flow_node_id: node.id,
          block_id: table.id,
          kind: "read",
          source_sheet: sheet.shortcut,
          source_variable: first_path
        })

      Repo.insert!(%VariableReference{
        source_type: "flow_node",
        source_id: node.id,
        flow_node_id: node.id,
        block_id: table.id,
        kind: "read",
        source_sheet: sheet.shortcut,
        source_variable: second_path
      })

      qualified = "#{sheet.shortcut}.#{first_path}"

      assert {:ok, %{items: [definition]}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_definition",
                 %{"block_id" => table.id, "qualified_ref" => qualified}
               )

      assert definition.destination.focus == %{
               type: :cell,
               block_id: table.id,
               row_id: row.id,
               column_id: first.id
             }

      assert {:ok, %{items: [usage]}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_usages",
                 %{"block_id" => table.id, "qualified_ref" => qualified}
               )

      assert usage.id == "variable-usage:#{first_reference.id}"
    end

    test "scene pin and zone reads navigate to their exact element",
         %{scope: scope, project: project, variable: variable} do
      scene = scene_fixture(project, %{name: "World"})
      pin = pin_fixture(scene, %{"label" => "Hero pin"})
      zone = zone_fixture(scene, %{"name" => "Danger zone"})

      for {source_type, source_id} <- [{"scene_pin", pin.id}, {"scene_zone", zone.id}] do
        Repo.insert!(%VariableReference{
          source_type: source_type,
          source_id: source_id,
          block_id: variable.id,
          kind: "read",
          source_sheet: "hero",
          source_variable: variable.variable_name
        })
      end

      assert {:ok, %{items: items}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "variable_usages",
                 %{
                   "block_id" => variable.id,
                   "qualified_ref" => "hero.#{variable.variable_name}"
                 }
               )

      assert MapSet.new(items, & &1.destination.focus) ==
               MapSet.new([%{type: :pin, id: pin.id}, %{type: :zone, id: zone.id}])
    end
  end

  describe "entity usages and flow callers" do
    test "returns active backlink sources and rejects a target from another project",
         %{scope: scope, project: project, sheet: target, user: user, workspace: workspace} do
      source_sheet = sheet_fixture(project, %{name: "Source", shortcut: "source"})
      source_block = block_fixture(source_sheet)

      Repo.insert!(%EntityReference{
        source_type: "block",
        source_id: source_block.id,
        target_type: "sheet",
        target_id: target.id,
        context: "reference"
      })

      assert {:ok, %{items: [hit]}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "entity_usages",
                 %{"type" => "sheet", "id" => target.id}
               )

      assert hit.destination == %{
               type: :sheet,
               id: source_sheet.id,
               focus: %{type: :block, id: source_block.id}
             }

      assert hit.kind == :entity_usage

      other_project = project_fixture(user, %{workspace: workspace})
      other_target = sheet_fixture(other_project)

      assert {:error, :not_found} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "entity_usages",
                 %{"type" => "sheet", "id" => other_target.id}
               )

      Repo.update_all(from(block in Block, where: block.id == ^source_block.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert {:ok, %{items: []}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "entity_usages",
                 %{"type" => "sheet", "id" => target.id}
               )
    end

    test "returns subflow callers without node JSON and excludes deleted nodes",
         %{scope: scope, project: project} do
      target = flow_fixture(project, %{name: "Target"})
      caller = flow_fixture(project, %{name: "Caller"})

      subflow =
        Repo.insert!(%FlowNode{
          flow_id: caller.id,
          type: "subflow",
          data: %{"referenced_flow_id" => to_string(target.id)}
        })

      exit =
        Repo.insert!(%FlowNode{
          flow_id: caller.id,
          type: "exit",
          data: %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => to_string(target.id)
          }
        })

      assert {:ok, %{items: items}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "flow_callers",
                 %{"id" => target.id}
               )

      assert MapSet.new(items, & &1.destination) ==
               MapSet.new([
                 %{type: :flow, id: caller.id, focus: %{type: :node, id: subflow.id}},
                 %{type: :flow, id: caller.id, focus: %{type: :node, id: exit.id}}
               ])

      assert Enum.all?(items, &(&1.kind == :flow_caller))
      refute inspect(items) =~ "referenced_flow_id"

      Repo.update_all(from(candidate in FlowNode, where: candidate.id in ^[subflow.id, exit.id]),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert {:ok, %{items: []}} =
               GlobalSearch.execute_reference_operation(
                 scope,
                 project.id,
                 "flow_callers",
                 %{"id" => target.id}
               )
    end
  end
end
