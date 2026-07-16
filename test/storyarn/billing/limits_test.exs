defmodule Storyarn.Billing.LimitsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Billing
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  describe "can_create_workspace?/1" do
    test "blocks when user already has a workspace", %{user: user} do
      assert {:error, :limit_reached, %{resource: :workspaces_per_user}} =
               Billing.can_create_workspace?(user)
    end

    test "allows for a user with no workspaces" do
      # Create a user without the default workspace by inserting directly
      user =
        %Storyarn.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: "nows#{System.unique_integer([:positive])}@test.com",
          confirmed_at: DateTime.utc_now(:second)
        })
        |> Repo.insert!()

      assert :ok = Billing.can_create_workspace?(user)
    end
  end

  describe "can_create_project?/1" do
    test "allows under limit", %{workspace: workspace} do
      assert :ok = Billing.can_create_project?(workspace)
    end

    test "blocks at limit", %{user: user, workspace: workspace} do
      scope = user_scope_fixture(user)

      for _ <- 1..3 do
        {:ok, _} =
          Storyarn.Projects.create_project(scope, %{
            name: "P#{System.unique_integer([:positive])}",
            workspace_id: workspace.id,
            project_type: "game",
            project_subtype: "rpg"
          })
      end

      assert {:error, :limit_reached, %{resource: :projects_per_workspace}} =
               Billing.can_create_project?(workspace)
    end
  end

  describe "can_invite_member?/1" do
    test "allows under limit for workspace", %{workspace: workspace} do
      # Workspace has 1 member (owner), limit is 2
      assert :ok = Billing.can_invite_member?(workspace)
    end

    test "blocks at limit for workspace", %{user: _user, workspace: workspace} do
      # Add a second member to reach the limit of 2
      other_user = user_fixture()
      workspace_membership_fixture(workspace, other_user)

      assert {:error, :limit_reached, %{resource: :members_per_workspace}} =
               Billing.can_invite_member?(workspace)
    end

    test "counts project-only members toward workspace limit", %{
      user: user,
      workspace: workspace
    } do
      # Create a project and add a member to it (not to the workspace)
      project = project_fixture(user, workspace: workspace)
      other_user = user_fixture()
      membership_fixture(project, other_user)

      # Now workspace has 2 unique users (owner + project member), at limit
      assert {:error, :limit_reached, %{resource: :members_per_workspace}} =
               Billing.can_invite_member?(workspace)
    end

    test "allows under limit for project", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      # Workspace has 1 member (owner), limit is 2
      assert :ok = Billing.can_invite_member?(project)
    end

    test "counts a pending project invitation toward the member limit", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)

      assert {:ok, _invitation} =
               Storyarn.Projects.create_invitation(
                 project,
                 user,
                 "pending@example.com",
                 "editor"
               )

      assert {:error, :limit_reached, %{resource: :members_per_workspace, used: 2, limit: 2}} =
               Billing.can_invite_member?(project)
    end

    test "blocks at limit for project (checks workspace limits)", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)
      # Add a second member to reach the workspace limit of 2
      other_user = user_fixture()
      workspace_membership_fixture(workspace, other_user)

      assert {:error, :limit_reached, %{resource: :members_per_workspace}} =
               Billing.can_invite_member?(project)
    end

    test "ignores legacy invitations and memberships from soft-deleted projects", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)

      {_token, invitation} =
        ProjectInvitation.build_invitation(
          project,
          user,
          "legacy-deleted-project@example.com",
          "editor"
        )

      Repo.insert!(invitation)

      assert {:error, :limit_reached, %{used: 2, limit: 2}} =
               Billing.can_invite_member?(workspace)

      project
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert :ok = Billing.can_invite_member?(workspace)
      assert Billing.count_unique_workspace_users(workspace.id) == 1
      assert Billing.usage(workspace).members.used == 1
    end
  end

  describe "can_create_item?/1" do
    test "allows under limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      assert :ok = Billing.can_create_item?(project)
    end

    test "reserves every item created by a compound operation", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Existing"})
      now = DateTime.utc_now(:second)

      entries =
        for i <- 1..695 do
          %{
            flow_id: flow.id,
            type: "dialogue",
            position_x: i * 1.0,
            position_y: 0.0,
            data: %{},
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(FlowNode, entries)

      assert Billing.count_project_items(project.id) == 698
      assert :ok = Billing.can_create_item?(project)

      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Flows.create_flow(project, %{name: "Needs three slots"})

      assert Billing.count_project_items(project.id) == 698
    end

    test "counts all item types: flows, nodes, sheets, scenes", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)

      # Create a flow (auto-creates entry + exit nodes) = 3 items
      {:ok, _flow} = Storyarn.Flows.create_flow(project, %{name: "Flow 1"})

      # Create a sheet = 1 item
      {:ok, _sheet} =
        Storyarn.Sheets.create_sheet(project, %{name: "Sheet 1"})

      # Create a scene = 1 item
      {:ok, _scene} =
        Storyarn.Scenes.create_scene(project, %{name: "Scene 1"})

      # Total: 1 flow + 2 nodes + 1 sheet + 1 scene = 5 items
      assert Billing.count_project_items(project.id) == 5
      assert :ok = Billing.can_create_item?(project)
    end

    test "blocks at limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)

      # Create a flow (auto-creates entry + exit nodes) = 3 items (1 flow + 2 nodes)
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test"})

      # Insert enough nodes to reach the limit of 700
      # Current items: 1 flow + 2 nodes = 3. Need 697 more.
      for i <- 1..697 do
        %FlowNode{flow_id: flow.id}
        |> FlowNode.create_changeset(%{
          type: "dialogue",
          position_x: i * 1.0,
          position_y: 0.0,
          data: %{}
        })
        |> Repo.insert!()
      end

      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Billing.can_create_item?(project)
    end

    test "does not count soft-deleted items", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)

      {:ok, _flow} = Storyarn.Flows.create_flow(project, %{name: "Flow"})
      {:ok, sheet} = Storyarn.Sheets.create_sheet(project, %{name: "Sheet"})
      {:ok, scene} = Storyarn.Scenes.create_scene(project, %{name: "Scene"})

      # 1 flow + 2 nodes + 1 sheet + 1 scene = 5
      assert Billing.count_project_items(project.id) == 5

      # Soft-delete sheet and scene
      now = DateTime.utc_now(:second)

      sheet |> Ecto.Changeset.change(deleted_at: now) |> Repo.update!()
      scene |> Ecto.Changeset.change(deleted_at: now) |> Repo.update!()

      # Should be 3 now (1 flow + 2 nodes)
      assert Billing.count_project_items(project.id) == 3
    end
  end

  describe "can_upload_asset?/1" do
    test "allows under storage limit", %{workspace: workspace} do
      assert :ok = Billing.can_upload_asset?(workspace, 50 * 1024 * 1024)
    end

    test "blocks when upload would exceed limit", %{workspace: workspace} do
      # 250MB limit, try to upload 300MB
      assert {:error, :limit_reached, %{resource: :storage_bytes_per_workspace}} =
               Billing.can_upload_asset?(workspace, 300 * 1024 * 1024)
    end
  end

  describe "can_upload_asset? with real storage" do
    test "blocks upload when existing storage plus new file exceeds limit", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)

      # Insert an asset that uses 200MB of storage
      %Asset{}
      |> Ecto.Changeset.change(%{
        filename: "big_file.zip",
        content_type: "application/zip",
        size: 200 * 1024 * 1024,
        key: "projects/#{project.id}/assets/big_file.zip",
        url: "https://example.com/big_file.zip",
        project_id: project.id,
        uploaded_by_id: user.id
      })
      |> Repo.insert!()

      # 200MB existing + 60MB new = 260MB > 250MB limit
      assert {:error, :limit_reached, %{resource: :storage_bytes_per_workspace, used: used}} =
               Billing.can_upload_asset?(workspace, 60 * 1024 * 1024)

      assert used == 200 * 1024 * 1024

      # 200MB existing + 40MB new = 240MB < 250MB limit
      assert :ok = Billing.can_upload_asset?(workspace, 40 * 1024 * 1024)
    end
  end

  describe "integration - CRUD modules enforce limits" do
    setup %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)

      # Create a flow (auto-creates entry + exit nodes) = 3 items
      {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Test"})

      # Bulk insert nodes to reach the limit of 700
      # Current items: 1 flow + 2 nodes = 3. Need 697 more.
      now = DateTime.utc_now(:second)

      entries =
        for i <- 1..697 do
          %{
            flow_id: flow.id,
            type: "dialogue",
            position_x: i * 1.0,
            position_y: 0.0,
            data: %{},
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(FlowNode, entries)

      %{project: project, flow: flow}
    end

    test "Flows.create_flow returns limit_reached at limit", %{project: project} do
      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Flows.create_flow(project, %{name: "Blocked"})
    end

    test "Flows.create_linked_flow returns limit_reached at limit", %{
      project: project,
      flow: flow
    } do
      # Get an existing node to link
      [node | _] = Repo.all(FlowNode)

      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Flows.create_linked_flow(project, flow, node)
    end

    test "Sheets.create_sheet returns limit_reached at limit", %{project: project} do
      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Sheets.create_sheet(project, %{name: "Blocked"})
    end

    test "Scenes.create_scene returns limit_reached at limit", %{project: project} do
      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Scenes.create_scene(project, %{name: "Blocked"})
    end

    test "Flows.NodeCreate returns limit_reached at limit", %{flow: flow} do
      assert {:error, :limit_reached, %{resource: :items_per_project}} =
               Storyarn.Flows.create_node(flow, %{
                 type: "dialogue",
                 position_x: 100.0,
                 position_y: 100.0
               })
    end
  end

  describe "can_create_named_version?/2" do
    test "allows under limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      assert :ok = Billing.can_create_named_version?(project.id, workspace.id)
    end

    test "blocks at limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project)
      sheet = Repo.preload(sheet, :blocks, force: true)

      # Create 10 named versions to reach the limit
      for i <- 1..10 do
        {:ok, _} =
          Storyarn.Versioning.create_version("sheet", sheet, project.id, user.id, title: "v#{i}")
      end

      assert {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} =
               Billing.can_create_named_version?(project.id, workspace.id)
    end

    test "counts promoted auto-snapshots toward limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      sheet = Storyarn.SheetsFixtures.sheet_fixture(project)
      sheet = Repo.preload(sheet, :blocks, force: true)

      # Create 9 named + 1 promoted = 10
      for i <- 1..9 do
        {:ok, _} =
          Storyarn.Versioning.create_version("sheet", sheet, project.id, user.id, title: "v#{i}")
      end

      {:ok, auto} =
        Storyarn.Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      # Still under limit (only 9 named, auto has no title)
      assert :ok = Billing.can_create_named_version?(project.id, workspace.id)

      # Promote the auto-snapshot
      {:ok, _} = Storyarn.Versioning.update_version(auto, %{title: "Promoted"})

      # Now at limit
      assert {:error, :limit_reached, _} =
               Billing.can_create_named_version?(project.id, workspace.id)
    end
  end

  describe "can_create_project_snapshot?/2" do
    test "allows under limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      assert :ok = Billing.can_create_project_snapshot?(project.id, workspace.id)
    end

    test "blocks at limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)

      for _ <- 1..10 do
        {:ok, _} = Storyarn.Versioning.create_project_snapshot(project.id, user.id)
      end

      assert {:error, :limit_reached, %{resource: :project_snapshots_per_project, used: 10, limit: 10}} =
               Billing.can_create_project_snapshot?(project.id, workspace.id)
    end
  end

  describe "can_upload_asset? boundary" do
    test "allows upload exactly at limit boundary", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      storage_limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)

      # Insert an asset that uses (limit - 1 byte) of storage
      %Asset{}
      |> Ecto.Changeset.change(%{
        filename: "big_file.zip",
        content_type: "application/zip",
        size: storage_limit - 1,
        key: "projects/#{project.id}/assets/big_file.zip",
        url: "https://example.com/big_file.zip",
        project_id: project.id,
        uploaded_by_id: user.id
      })
      |> Repo.insert!()

      # 1 byte upload should succeed (used + new = limit exactly)
      assert :ok = Billing.can_upload_asset?(workspace, 1)

      # 2 bytes should fail (used + new > limit)
      assert {:error, :limit_reached, %{resource: :storage_bytes_per_workspace}} =
               Billing.can_upload_asset?(workspace, 2)
    end
  end

  describe "unique user counting" do
    test "user with both workspace and project membership counts as one", %{
      user: user,
      workspace: workspace
    } do
      # user already has workspace membership (owner, from setup)
      project = project_fixture(user, workspace: workspace)

      # Add user as project member too (they already have workspace membership)
      # The owner already has a ProjectMembership from create_project, so count should be 1
      assert Billing.count_unique_workspace_users(workspace.id) == 1

      # Add another user with BOTH workspace and project membership
      other_user = user_fixture()
      workspace_membership_fixture(workspace, other_user)
      membership_fixture(project, other_user)

      # Should be 2 unique users, not 3 or 4
      assert Billing.count_unique_workspace_users(workspace.id) == 2
    end
  end

  describe "usage/1" do
    test "returns correct counts", %{user: user, workspace: workspace} do
      _project = project_fixture(user, workspace: workspace)

      usage = Billing.usage(workspace)

      assert usage.plan == "free"
      assert usage.projects.used == 1
      assert usage.projects.limit == 3
      assert usage.members.used == 1
      assert usage.members.limit == 2
      assert usage.storage_bytes.used == 0
      assert usage.storage_bytes.limit == 250 * 1024 * 1024
    end

    test "reports pending invitations as occupied member seats", %{
      user: user,
      workspace: workspace
    } do
      project = project_fixture(user, workspace: workspace)

      assert {:ok, _invitation} =
               Storyarn.Projects.create_invitation(
                 project,
                 user,
                 "pending-usage@example.com",
                 "editor"
               )

      assert Billing.usage(workspace).members == %{used: 2, limit: 2}
      assert Billing.project_limits_usage(project).workspace.members == %{used: 2, limit: 2}
    end
  end
end
