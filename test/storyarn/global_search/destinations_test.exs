defmodule Storyarn.GlobalSearch.DestinationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.GlobalSearch
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})

    %{user: user, scope: scope, workspace: workspace, project: project}
  end

  describe "authorization boundary" do
    test "a user NEVER sees another user's workspaces, projects, or entities", %{scope: scope} do
      intruder_target = user_fixture()
      other_workspace = workspace_fixture(intruder_target)
      other_project = project_fixture(intruder_target, %{workspace: other_workspace})
      sheet_fixture(other_project, %{name: "Secret Kael"})

      result = GlobalSearch.destinations(scope, "")

      refute Enum.any?(result.workspaces, &(&1.id == other_workspace.id))
      refute Enum.any?(result.projects, &(&1.id == other_project.id))

      result = GlobalSearch.destinations(scope, "Secret Kael")
      assert result.entities == []
    end

    test "workspace members see workspace projects; outside projects need direct membership",
         %{scope: scope, workspace: workspace, user: user} do
      owner = user_fixture()
      foreign_workspace = workspace_fixture(owner)
      foreign_project = project_fixture(owner, %{workspace: foreign_workspace})

      # No direct membership on the foreign project -> invisible.
      result = GlobalSearch.destinations(scope, "")
      refute Enum.any?(result.projects, &(&1.id == foreign_project.id))

      # Direct project membership makes exactly that project (and its workspace) visible.
      membership_fixture(foreign_project, user, "viewer")

      result = GlobalSearch.destinations(scope, "")
      assert Enum.any?(result.projects, &(&1.id == foreign_project.id))
      assert Enum.any?(result.workspaces, &(&1.id == foreign_workspace.id))
      assert Enum.any?(result.workspaces, &(&1.id == workspace.id))
    end
  end

  describe "entity search" do
    test "finds entities across the user's projects with project context",
         %{scope: scope, project: project, workspace: workspace} do
      sheet = sheet_fixture(project, %{name: "Kael the Wanderer"})
      flow_fixture(project, %{name: "Kael intro"})
      scene_fixture(project, %{name: "Kael hideout"})

      result = GlobalSearch.destinations(scope, "kael")

      assert result.entities |> Enum.map(& &1.type) |> Enum.sort() == [:flow, :scene, :sheet]

      sheet_hit = Enum.find(result.entities, &(&1.type == :sheet))
      assert sheet_hit.id == sheet.id
      assert sheet_hit.project_slug == project.slug
      assert sheet_hit.project_name == project.name
      assert sheet_hit.workspace_slug == workspace.slug
    end

    test "excludes soft-deleted entities", %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Ghost sheet"})
      {:ok, _} = Sheets.delete_sheet(sheet)

      assert GlobalSearch.destinations(scope, "Ghost").entities == []
    end

    test "requires two characters and caps the query length", %{scope: scope, project: project} do
      sheet_fixture(project, %{name: "K"})

      assert GlobalSearch.destinations(scope, "K").entities == []
      # Characters, not bytes: one multibyte character is still one character.
      assert GlobalSearch.destinations(scope, "ñ").entities == []

      long_query = String.duplicate("a", 5_000)
      assert %{entities: []} = GlobalSearch.destinations(scope, long_query)
    end

    test "ILIKE wildcards in the query are literals, not patterns",
         %{scope: scope, project: project} do
      sheet_fixture(project, %{name: "Totally Normal"})
      sheet_fixture(project, %{name: "100% done"})

      result = GlobalSearch.destinations(scope, "100%")
      assert Enum.map(result.entities, & &1.name) == ["100% done"]

      assert GlobalSearch.destinations(scope, "%%").entities == []
    end

    test "respects the per-type limit", %{scope: scope, project: project} do
      for n <- 1..10, do: sheet_fixture(project, %{name: "Limited #{n}"})

      result = GlobalSearch.destinations(scope, "Limited", limit_per_type: 3)
      assert length(result.entities) == 3
    end
  end

  describe "workspace and project matching" do
    test "empty query lists everything accessible; non-empty filters by name",
         %{scope: scope, workspace: workspace, project: project, user: user} do
      other_project = project_fixture(user, %{workspace: workspace, name: "Zeta Station"})

      empty = GlobalSearch.destinations(scope, "")
      assert Enum.any?(empty.projects, &(&1.id == project.id))
      assert Enum.any?(empty.projects, &(&1.id == other_project.id))

      filtered = GlobalSearch.destinations(scope, "zeta")
      assert Enum.map(filtered.projects, & &1.id) == [other_project.id]
      assert Enum.all?(filtered.projects, &(&1.workspace_slug == workspace.slug))
    end
  end
end
