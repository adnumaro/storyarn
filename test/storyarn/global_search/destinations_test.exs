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

  describe "create_targets/1" do
    test "lists projects with edit rights, with workspace context",
         %{scope: scope, project: project, workspace: workspace} do
      targets = GlobalSearch.create_targets(scope)

      assert [%{id: id, name: name, workspace_name: workspace_name}] = targets
      assert id == project.id
      assert name == project.name
      assert workspace_name == workspace.name
    end

    test "excludes view-only access at both membership levels", %{user: user, scope: scope} do
      owner = user_fixture()

      viewer_workspace = workspace_fixture(owner)
      workspace_membership_fixture(viewer_workspace, user, "viewer")
      ws_viewer_project = project_fixture(owner, %{workspace: viewer_workspace})

      foreign_workspace = workspace_fixture(owner)
      pm_viewer_project = project_fixture(owner, %{workspace: foreign_workspace})
      membership_fixture(pm_viewer_project, user, "viewer")

      target_ids = scope |> GlobalSearch.create_targets() |> Enum.map(& &1.id)

      refute ws_viewer_project.id in target_ids
      refute pm_viewer_project.id in target_ids

      # Both remain NAVIGABLE — view access is enough for destinations.
      nav_ids = Enum.map(GlobalSearch.destinations(scope, "").projects, & &1.id)
      assert ws_viewer_project.id in nav_ids
      assert pm_viewer_project.id in nav_ids
    end

    test "a direct editor membership on a foreign project grants a create target", %{user: user, scope: scope} do
      owner = user_fixture()
      foreign_project = project_fixture(owner, %{workspace: workspace_fixture(owner)})
      membership_fixture(foreign_project, user, "editor")

      assert foreign_project.id in (scope |> GlobalSearch.create_targets() |> Enum.map(& &1.id))
    end

    test "never includes another user's projects", %{scope: scope} do
      other = user_fixture()
      other_project = project_fixture(other, %{workspace: workspace_fixture(other)})

      refute other_project.id in (scope |> GlobalSearch.create_targets() |> Enum.map(& &1.id))
    end
  end

  describe "editable_project/2" do
    test "authorizes an editable project id", %{scope: scope, project: project, workspace: workspace} do
      assert {:ok, %{project: found, workspace: found_workspace}} =
               GlobalSearch.editable_project(scope, project.id)

      assert found.id == project.id
      assert found_workspace.slug == workspace.slug
    end

    test "rejects foreign and view-only project ids", %{user: user, scope: scope} do
      owner = user_fixture()
      foreign_project = project_fixture(owner, %{workspace: workspace_fixture(owner)})

      assert {:error, :unauthorized} = GlobalSearch.editable_project(scope, foreign_project.id)

      membership_fixture(foreign_project, user, "viewer")
      assert {:error, :unauthorized} = GlobalSearch.editable_project(scope, foreign_project.id)
    end
  end

  describe "deletable_entities/3" do
    test "empty query lists recent entities from editable projects, with project_id",
         %{scope: scope, project: project} do
      sheet = sheet_fixture(project, %{name: "Recent sheet"})

      items = GlobalSearch.deletable_entities(scope, "")

      hit = Enum.find(items, &(&1.type == :sheet and &1.id == sheet.id))
      assert hit.project_id == project.id
    end

    test "excludes entities from view-only projects even on name match", %{user: user, scope: scope} do
      owner = user_fixture()
      foreign_project = project_fixture(owner, %{workspace: workspace_fixture(owner)})
      membership_fixture(foreign_project, user, "viewer")
      sheet_fixture(foreign_project, %{name: "Readonly Relic"})

      assert GlobalSearch.deletable_entities(scope, "Readonly Relic") == []
      # Still discoverable through plain navigation search.
      assert [_] = GlobalSearch.destinations(scope, "Readonly Relic").entities
    end
  end

  describe "deletable_entity/4" do
    test "loads an entity for deletion within an editable project", %{scope: scope, project: project} do
      sheet = sheet_fixture(project)

      assert {:ok, %{entity: entity, project: found_project, workspace: _}} =
               GlobalSearch.deletable_entity(scope, :sheet, project.id, sheet.id)

      assert entity.id == sheet.id
      assert found_project.id == project.id
    end

    test "rejects a project the scope cannot edit even with a valid entity id", %{user: user, scope: scope} do
      owner = user_fixture()
      foreign_project = project_fixture(owner, %{workspace: workspace_fixture(owner)})
      membership_fixture(foreign_project, user, "viewer")
      sheet = sheet_fixture(foreign_project)

      assert {:error, :unauthorized} =
               GlobalSearch.deletable_entity(scope, :sheet, foreign_project.id, sheet.id)
    end

    test "an entity outside the claimed project or already trashed is not found",
         %{scope: scope, project: project, user: user, workspace: workspace} do
      other_project = project_fixture(user, %{workspace: workspace})
      sheet = sheet_fixture(other_project)

      # Editable project + entity id from ANOTHER project: scoped load fails.
      assert {:error, :not_found} = GlobalSearch.deletable_entity(scope, :sheet, project.id, sheet.id)

      trashed = sheet_fixture(project)
      {:ok, _} = Sheets.delete_sheet(trashed)
      assert {:error, :not_found} = GlobalSearch.deletable_entity(scope, :sheet, project.id, trashed.id)
    end
  end
end
