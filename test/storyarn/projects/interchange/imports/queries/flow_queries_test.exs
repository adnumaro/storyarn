defmodule Storyarn.Projects.Imports.FlowQueriesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Imports.FlowQueries

  test "returns only the active main flow identity" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)

    _regular = flow_fixture(project, %{name: "Regular", is_main: false})
    _other_main = flow_fixture(other_project, %{name: "Other Main", is_main: true})

    assert FlowQueries.get_active_main_identity(project.id) == nil

    main = flow_fixture(project, %{name: "Main", shortcut: "main", is_main: true})
    assert FlowQueries.get_active_main_identity(project.id) == %{shortcut: main.shortcut}

    assert {:ok, _trashed} = Flows.delete_flow(main)
    assert FlowQueries.get_active_main_identity(project.id) == nil
  end
end
