defmodule Storyarn.Sheets.Logic.Queries.VariableNamespacesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets.Logic
  alias Storyarn.Sheets.Logic.Queries.VariableNamespaces

  test "explicit numeric shortcuts take precedence over an ID fallback without planner ambiguity" do
    project = project_fixture()
    fallback_sheet = sheet_fixture(project, %{name: "Fallback namespace"})
    explicit_sheet = sheet_fixture(project, %{name: "Explicit namespace"})
    namespace = Integer.to_string(fallback_sheet.id)

    fallback_sheet = Repo.update!(Ecto.Changeset.change(fallback_sheet, shortcut: nil))
    explicit_sheet = Repo.update!(Ecto.Changeset.change(explicit_sheet, shortcut: namespace))

    assert VariableNamespaces.resolve_sheet_id(project.id, namespace) == explicit_sheet.id

    assert VariableNamespaces.resolve_sheet_ids(project.id, [namespace]) == %{
             namespace => explicit_sheet.id
           }

    Repo.update!(
      Ecto.Changeset.change(explicit_sheet,
        deleted_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
    )

    assert VariableNamespaces.resolve_sheet_id(project.id, namespace) == fallback_sheet.id
  end

  test "ID fallback is exact, active, and project scoped" do
    project = project_fixture()
    other_project = project_fixture()
    sheet = sheet_fixture(project, %{name: "Shortcutless"})
    other_sheet = sheet_fixture(other_project, %{name: "Other"})
    namespace = Integer.to_string(sheet.id)

    Repo.update!(Ecto.Changeset.change(sheet, shortcut: nil))
    Repo.update!(Ecto.Changeset.change(other_sheet, shortcut: namespace))

    assert VariableNamespaces.resolve_sheet_id(project.id, namespace) == sheet.id
    assert VariableNamespaces.resolve_sheet_id(project.id, "0#{namespace}") == nil
    assert VariableNamespaces.resolve_sheet_id(project.id, "") == nil
  end

  test "runtime and catalog surfaces expose only the authoritative numeric namespace owner" do
    project = project_fixture()
    fallback_sheet = sheet_fixture(project, %{name: "Fallback namespace"})
    explicit_sheet = sheet_fixture(project, %{name: "Explicit namespace"})
    namespace = Integer.to_string(fallback_sheet.id)

    Repo.update!(Ecto.Changeset.change(fallback_sheet, shortcut: nil))
    Repo.update!(Ecto.Changeset.change(explicit_sheet, shortcut: namespace))

    fallback_block =
      block_fixture(fallback_sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 10}
      })

    explicit_block =
      block_fixture(explicit_sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => 20}
      })

    qualified_ref = "#{namespace}.#{explicit_block.variable_name}"

    assert Logic.resolve_variable_values(project.id, [qualified_ref]) == %{
             qualified_ref => 20
           }

    variable_block_ids =
      project.id
      |> Logic.list_project_variables()
      |> Enum.map(& &1.block_id)

    assert explicit_block.id in variable_block_ids
    refute fallback_block.id in variable_block_ids

    assert %{items: [%{block_id: block_id}], truncated: false} =
             Logic.list_definitions(
               project.id,
               {:qualified, qualified_ref},
               limit: 10
             )

    assert block_id == explicit_block.id
  end
end
