defmodule Storyarn.Projects.SheetHealthReadModelTest do
  @moduledoc """
  Pins that the Project-owned Sheet health sweep agrees finding-for-finding
  with the Sheet tool's own dashboard sweep, which it duplicates.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  test "agrees with the Sheet tool sweep on an empty project", %{project: project} do
    assert Projects.list_sheet_dashboard_health_findings(project.id) ==
             Sheets.list_dashboard_health_findings(project.id)

    assert Projects.sheet_referenced_block_ids(project.id) ==
             Sheets.referenced_block_ids_for_project(project.id)
  end

  test "agrees with the Sheet tool sweep finding-for-finding", %{project: project} do
    parent = sheet_fixture(project, %{name: "Parent", shortcut: "parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child", shortcut: "child"})

    # A labeled variable nobody references — the unused-variable finding.
    block_fixture(parent, %{type: "number", config: %{"label" => "Health"}})

    # An inheritable definition so the child carries inherited state.
    inheritable_block_fixture(parent, label: "Shared trait")

    # A table with a formula column, exercising the table snapshot slice.
    table = table_block_fixture(child, %{label: "Stats"})
    table_row_fixture(table, %{name: "Strength"})
    table_column_fixture(table, %{name: "Value", type: "number"})

    # A reference block whose target goes to trash — the stale-reference finding.
    target = sheet_fixture(project, %{name: "Doomed", shortcut: "doomed"})

    block_fixture(child, %{
      type: "reference",
      value: %{"target_type" => "sheet", "target_id" => target.id}
    })

    {:ok, _} = Sheets.delete_sheet(target)

    # A flow-node variable reference so referenced ids are non-trivial.
    flow = flow_fixture(project)

    node_fixture(flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{
            "id" => Ecto.UUID.generate(),
            "sheet" => "parent",
            "variable" => "health",
            "operator" => "set",
            "value" => "1",
            "value_type" => "literal"
          }
        ]
      }
    })

    tool_referenced = Sheets.referenced_block_ids_for_project(project.id)
    project_referenced = Projects.sheet_referenced_block_ids(project.id)

    assert project_referenced == tool_referenced

    tool_findings = Sheets.list_dashboard_health_findings(project.id, tool_referenced)
    project_findings = Projects.list_sheet_dashboard_health_findings(project.id, project_referenced)

    assert sort_findings(project_findings) == sort_findings(tool_findings)
    assert project_findings != []
  end

  defp sort_findings(findings) do
    Enum.sort_by(findings, &{&1.code, &1.block_id, &1.row_id, &1.column_id, inspect(&1.details)})
  end
end
