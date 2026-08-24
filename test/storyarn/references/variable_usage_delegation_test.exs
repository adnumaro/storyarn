defmodule Storyarn.References.VariableUsageDelegationTest do
  @moduledoc """
  The batched stale-reference sweep used to travel
  `References → VariableUsage → legacy variable tracker → Sheets → SheetQueries`.
  It now reads Project-owned records through
  `Projects.FlowVariableReferenceReadModel`; the behaviour is asserted
  end-to-end because a pure structural assertion would pass just as well
  against a broken repoint.

  The single-flow `list_stale_node_ids/1` chain is deliberately NOT collapsed —
  its third hop unions two real queries.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.FlowVariableReferenceReadModel
  alias Storyarn.References
  alias Storyarn.References.VariableUsage
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)

    sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})
    block = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

    # A table cell reference spells its path as `sheet.table.row.column`, so it
    # can go stale two independent ways: the shortcut changes, or the row/column
    # that named it is deleted. The second has its own subquery.
    table = table_block_fixture(sheet, %{label: "Attributes"})
    row = table_row_fixture(table, %{name: "Strength"})
    column = table_column_fixture(table, %{name: "Value", type: "number"})

    flow = flow_fixture(project)
    node = tracked_assignment_node(flow, "hero", block.variable_name)
    cell_node = tracked_assignment_node(flow, "hero", "#{table.variable_name}.#{row.slug}.#{column.slug}")

    %{
      project: project,
      sheet: sheet,
      block: block,
      table: table,
      row: row,
      column: column,
      flow: flow,
      node: node,
      cell_node: cell_node
    }
  end

  describe "the batched sweep no longer detours through Flows" do
    test "VariableUsage stops re-exporting the batched sweep", _context do
      refute {:list_stale_node_ids_by_flow, 1} in exported_functions(VariableUsage),
             "VariableUsage still re-exports the batched sweep; References should read Project-owned records"

      refute {:list_stale_node_ids_by_flow, 1} in exported_functions(References),
             "the id-only batched view had no remaining caller and must stay deleted"
    end

    test "the single-flow chain is left intact (it does real work)", _context do
      assert {:list_stale_node_ids, 1} in exported_functions(VariableUsage),
             "list_stale_node_ids/1 must keep its VariableUsage hop — hop 3 unions two queries"
    end
  end

  describe "References.list_stale_node_variable_refs_by_flow/1 after the repoint" do
    test "reports nothing while the reference still resolves", context do
      assert References.list_stale_node_variable_refs_by_flow([context.flow.id]) == %{}
    end

    test "reports both nodes once the sheet shortcut is renamed", context do
      {:ok, _sheet} = Sheets.update_sheet(context.sheet, %{shortcut: "protagonist"})

      assert stale_node_ids(context.flow.id) == MapSet.new([context.node.id, context.cell_node.id]),
             "the shortcut is half of every reference, table cells included"
    end

    test "reports only the cell node when a deleted table row breaks its path", context do
      # `update_table_row/2` keeps the slug on rename, so only removing the row
      # can break the cell — the plain reference is untouched either way.
      {:ok, _row} = Sheets.delete_table_row(context.row)

      assert stale_node_ids(context.flow.id) == MapSet.new([context.cell_node.id])
    end

    test "reports both causes at once without double-counting", context do
      {:ok, _sheet} = Sheets.update_sheet(context.sheet, %{shortcut: "protagonist"})
      {:ok, _row} = Sheets.delete_table_row(context.row)

      # The cell node is stale for BOTH reasons here. The two SQL builders are
      # unioned, so it must appear once, not twice — a MapSet makes that
      # structural, but the plain node must still be present alongside it.
      assert stale_node_ids(context.flow.id) == MapSet.new([context.node.id, context.cell_node.id])
    end

    test "keys each flow separately when several are asked for at once", context do
      other_flow = flow_fixture(context.project)
      other_node = tracked_assignment_node(other_flow, "hero", "health")

      {:ok, _sheet} = Sheets.update_sheet(context.sheet, %{shortcut: "protagonist"})
      {:ok, _row} = Sheets.delete_table_row(context.row)

      batched = References.list_stale_node_variable_refs_by_flow([context.flow.id, other_flow.id])

      assert batched |> Map.fetch!(other_flow.id) |> Map.keys() |> MapSet.new() == MapSet.new([other_node.id])

      assert batched |> Map.fetch!(context.flow.id) |> Map.keys() |> MapSet.new() ==
               MapSet.new([context.node.id, context.cell_node.id])
    end

    test "retains each stale full reference while deriving the node-id view", context do
      {:ok, _sheet} = Sheets.update_sheet(context.sheet, %{shortcut: "protagonist"})

      plain_ref = "hero.#{context.block.variable_name}"
      table_ref = "hero.#{context.table.variable_name}.#{context.row.slug}.#{context.column.slug}"

      assert References.list_stale_node_variable_refs_by_flow([context.flow.id]) == %{
               context.flow.id => %{
                 context.node.id => MapSet.new([plain_ref]),
                 context.cell_node.id => MapSet.new([table_ref])
               }
             }
    end

    test "retains the table-cell path when only that reference becomes stale", context do
      {:ok, _row} = Sheets.delete_table_row(context.row)

      table_ref = "hero.#{context.table.variable_name}.#{context.row.slug}.#{context.column.slug}"

      assert References.list_stale_node_variable_refs_by_flow([context.flow.id]) ==
               %{
                 context.flow.id => %{
                   context.cell_node.id => MapSet.new([table_ref])
                 }
               }
    end

    test "agrees with the Projects read model it now delegates to", context do
      {:ok, _sheet} = Sheets.update_sheet(context.sheet, %{shortcut: "protagonist"})

      assert References.list_stale_node_variable_refs_by_flow([context.flow.id]) ==
               FlowVariableReferenceReadModel.list_stale_node_variable_refs_by_flow([context.flow.id])
    end

    test "short-circuits on an empty flow list", _context do
      assert References.list_stale_node_variable_refs_by_flow([]) == %{}
    end
  end

  defp stale_node_ids(flow_id) do
    [flow_id]
    |> References.list_stale_node_variable_refs_by_flow()
    |> Map.get(flow_id, %{})
    |> Map.keys()
    |> MapSet.new()
  end

  # `function_exported?/3` answers `false` for a module that merely has not been
  # loaded yet, which would make the shim assertions pass for the wrong reason.
  defp exported_functions(module) do
    {:module, ^module} = Code.ensure_loaded(module)
    module.__info__(:functions)
  end

  # An instruction node that writes `sheet.variable`, with the reference recorded —
  # the same tracking the flow editor performs when a node is saved.
  defp tracked_assignment_node(flow, sheet_shortcut, variable_name) do
    node =
      node_fixture(flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "set",
              "value" => "1",
              "value_type" => "literal"
            }
          ]
        }
      })

    node
  end
end
