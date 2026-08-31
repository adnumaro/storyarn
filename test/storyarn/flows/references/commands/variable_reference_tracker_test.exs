defmodule Storyarn.Flows.VariableReferenceTrackerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Flows.VariableReferenceTracker

  setup do
    project = project_fixture(user_fixture())
    flow = flow_fixture(project)
    sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"}
      })

    %{project: project, flow: flow, sheet: sheet, block: block}
  end

  test "writes and deletes the Flow-owned variable-reference projection", context do
    node = instruction_node(context)

    assert :ok = VariableReferenceTracker.update_references(node)

    assert %VariableReference{
             source_type: "flow_node",
             source_id: source_id,
             flow_node_id: flow_node_id,
             block_id: block_id,
             kind: "write",
             source_sheet: "hero",
             source_variable: "health"
           } =
             Repo.get_by!(VariableReference,
               source_type: "flow_node",
               source_id: node.id
             )

    assert source_id == node.id
    assert flow_node_id == node.id
    assert block_id == context.block.id

    assert :ok = VariableReferenceTracker.delete_references(node.id)

    refute Repo.get_by(VariableReference,
             source_type: "flow_node",
             source_id: node.id
           )
  end

  test "certifies current rows and rejects stale projection metadata", context do
    node = instruction_node(context)
    assert :ok = VariableReferenceTracker.update_references(node)

    assert VariableReferenceTracker.flow_node_references_current_ids(
             [node],
             context.project.id
           ) == MapSet.new([node.id])

    reference =
      Repo.get_by!(VariableReference,
        source_type: "flow_node",
        source_id: node.id
      )

    reference
    |> Ecto.Changeset.change(source_sheet: "renamed")
    |> Repo.update!()

    assert VariableReferenceTracker.flow_node_references_current_ids(
             [node],
             context.project.id
           ) == MapSet.new()
  end

  test "detects stale references without consulting the Sheets context", context do
    node = instruction_node(context)
    assert :ok = VariableReferenceTracker.update_references(node)

    context.sheet
    |> Ecto.Changeset.change(shortcut: "renamed")
    |> Repo.update!()

    assert VariableReferenceTracker.list_stale_node_ids(context.flow.id) ==
             MapSet.new([node.id])
  end

  test "preserves an unresolved row while its exact authored identity remains", context do
    node = instruction_node(context)
    assert :ok = VariableReferenceTracker.update_references(node)

    original_reference =
      Repo.get_by!(VariableReference,
        source_type: "flow_node",
        source_id: node.id
      )

    context.sheet
    |> Ecto.Changeset.change(shortcut: "renamed")
    |> Repo.update!()

    assert {:ok, %{node: edited_node}} =
             Flows.edit_node(context.flow.id, node.id, :put_field, %{
               field: "description",
               value: "Unrelated edit"
             })

    assert edited_node.data["description"] == "Unrelated edit"

    assert %VariableReference{
             id: preserved_id,
             block_id: block_id,
             kind: "write",
             source_sheet: "hero",
             source_variable: "health"
           } =
             Repo.get_by!(VariableReference,
               source_type: "flow_node",
               source_id: node.id
             )

    assert preserved_id == original_reference.id
    assert block_id == context.block.id

    assert VariableReferenceTracker.list_stale_node_ids(context.flow.id) ==
             MapSet.new([node.id])
  end

  test "does not preserve stale rows whose authored identity is removed or replaced", context do
    removed_node = instruction_node(context)
    replaced_node = instruction_node(context)

    assert :ok = VariableReferenceTracker.update_references(removed_node)
    assert :ok = VariableReferenceTracker.update_references(replaced_node)

    removed_reference =
      Repo.get_by!(VariableReference,
        source_type: "flow_node",
        source_id: removed_node.id
      )

    replaced_reference =
      Repo.get_by!(VariableReference,
        source_type: "flow_node",
        source_id: replaced_node.id
      )

    replacement_sheet = sheet_fixture(context.project, %{name: "Quests", shortcut: "quests"})

    replacement_block =
      block_fixture(replacement_sheet, %{
        type: "boolean",
        config: %{"label" => "Started"}
      })

    context.sheet
    |> Ecto.Changeset.change(shortcut: "renamed")
    |> Repo.update!()

    assert {:ok, %{node: removed}} =
             Flows.edit_node(context.flow.id, removed_node.id, :put_instruction_assignments, %{
               assignments: []
             })

    replacement_assignments = [
      %{
        "sheet" => replacement_sheet.shortcut,
        "variable" => replacement_block.variable_name,
        "value_type" => "literal",
        "value" => true
      }
    ]

    assert {:ok, %{node: replaced}} =
             Flows.edit_node(context.flow.id, replaced_node.id, :put_instruction_assignments, %{
               assignments: replacement_assignments
             })

    assert removed.data["assignments"] == []

    assert [replaced_assignment] = replaced.data["assignments"]
    assert replaced_assignment["sheet"] == replacement_sheet.shortcut
    assert replaced_assignment["variable"] == replacement_block.variable_name
    assert replaced_assignment["value"] == true

    refute Repo.get(VariableReference, removed_reference.id)
    refute Repo.get(VariableReference, replaced_reference.id)

    refute Repo.get_by(VariableReference,
             source_type: "flow_node",
             source_id: removed_node.id
           )

    assert %VariableReference{
             block_id: replacement_block_id,
             source_sheet: "quests",
             source_variable: replacement_variable
           } =
             Repo.get_by!(VariableReference,
               source_type: "flow_node",
               source_id: replaced_node.id
             )

    assert replacement_block_id == replacement_block.id
    assert replacement_variable == replacement_block.variable_name
  end

  test "validates snapshot targets and fails closed on malformed assignments", context do
    valid_node = %{
      "original_id" => 101,
      "type" => "instruction",
      "data" => %{
        "assignments" => [
          %{
            "sheet" => context.sheet.shortcut,
            "variable" => context.block.variable_name,
            "value_type" => "literal",
            "value" => 10
          }
        ]
      }
    }

    assert :ok =
             VariableReferenceTracker.validate_flow_node_variable_targets(
               [valid_node],
               context.project.id
             )

    other_project = project_fixture()

    assert {:error, {:unresolved_variable_reference, "flow_node", 101, "write", "hero", "health"}} =
             VariableReferenceTracker.validate_flow_node_variable_targets(
               [valid_node],
               other_project.id
             )

    malformed = put_in(valid_node, ["data", "assignments"], nil)

    assert {:error, {:malformed_variable_reference, "flow_node", 101, :assignments, nil}} =
             VariableReferenceTracker.validate_flow_node_variable_targets(
               [malformed],
               context.project.id
             )
  end

  defp instruction_node(context) do
    node_fixture(context.flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{
            "sheet" => context.sheet.shortcut,
            "variable" => context.block.variable_name,
            "value_type" => "literal",
            "value" => 10
          }
        ]
      }
    })
  end
end
