defmodule Storyarn.Billing.LimitsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Billing

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

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
        |> Storyarn.Repo.insert!()

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
            workspace_id: workspace.id
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
  end

  describe "can_create_item?/1" do
    test "allows under limit", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      assert :ok = Billing.can_create_item?(project)
    end

    test "counts all item types: flows, nodes, sheets, scenes", %{user: user, workspace: workspace} do
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
        %Storyarn.Flows.FlowNode{flow_id: flow.id}
        |> Storyarn.Flows.FlowNode.create_changeset(%{
          type: "dialogue",
          position_x: i * 1.0,
          position_y: 0.0,
          data: %{}
        })
        |> Storyarn.Repo.insert!()
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

      sheet |> Ecto.Changeset.change(deleted_at: now) |> Storyarn.Repo.update!()
      scene |> Ecto.Changeset.change(deleted_at: now) |> Storyarn.Repo.update!()

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
      %Storyarn.Assets.Asset{}
      |> Ecto.Changeset.change(%{
        filename: "big_file.zip",
        content_type: "application/zip",
        size: 200 * 1024 * 1024,
        key: "projects/#{project.id}/assets/big_file.zip",
        url: "https://example.com/big_file.zip",
        project_id: project.id,
        uploaded_by_id: user.id
      })
      |> Storyarn.Repo.insert!()

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

      Storyarn.Repo.insert_all(Storyarn.Flows.FlowNode, entries)

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
      [node | _] = Storyarn.Repo.all(Storyarn.Flows.FlowNode)

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

  describe "can_upload_asset? boundary" do
    test "allows upload exactly at limit boundary", %{user: user, workspace: workspace} do
      project = project_fixture(user, workspace: workspace)
      storage_limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)

      # Insert an asset that uses (limit - 1 byte) of storage
      %Storyarn.Assets.Asset{}
      |> Ecto.Changeset.change(%{
        filename: "big_file.zip",
        content_type: "application/zip",
        size: storage_limit - 1,
        key: "projects/#{project.id}/assets/big_file.zip",
        url: "https://example.com/big_file.zip",
        project_id: project.id,
        uploaded_by_id: user.id
      })
      |> Storyarn.Repo.insert!()

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
  end
end
