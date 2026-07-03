defmodule Storyarn.ProjectTemplatesTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.AssetsFixtures
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.FlowsFixtures
  alias Storyarn.ProjectsFixtures
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.ScenesFixtures
  alias Storyarn.Sheets.Sheet
  alias Storyarn.SheetsFixtures
  alias Storyarn.WorkspacesFixtures

  describe "create_template_from_project/3" do
    test "creates a private template with an immutable v1 artifact" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Veilbreak"})

      assert {:ok, template} =
               ProjectTemplates.create_template_from_project(scope, project, %{
                 name: "Veilbreak Demo",
                 description: "A playable sample project"
               })

      assert template.owner_id == user.id
      assert template.source_project_id == project.id
      assert template.name == "Veilbreak Demo"
      assert template.slug == "veilbreak-demo"
      assert template.visibility == "private"
      assert template.current_version_id

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      assert version.project_template_id == template.id
      assert version.version_number == 1
      assert version.source_project_id == project.id
      assert version.snapshot_storage_key =~ "project_templates/#{template.id}/versions/1/snapshot-"
      assert version.asset_manifest_storage_key =~ "project_templates/#{template.id}/versions/1/asset-manifest-"
      assert version.checksum =~ ~r/^[a-f0-9]{64}$/
      assert version.audit_report["status"] == "passed"
    end

    test "does not allow public visibility through the normal API" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)

      assert {:error, :public_visibility_requires_admin} =
               ProjectTemplates.create_template_from_project(scope, project, %{
                 name: "Official Demo",
                 visibility: "public"
               })
    end
  end

  describe "publish_new_version/3" do
    test "creates a new current version without mutating previous versions" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Versioned Project"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Template"})
      first_version_id = template.current_version_id
      first_version = Repo.get!(ProjectTemplateVersion, first_version_id)

      assert {:ok, updated_template} = ProjectTemplates.publish_new_version(scope, template, project)

      assert updated_template.current_version_id != first_version_id
      second_version = Repo.get!(ProjectTemplateVersion, updated_template.current_version_id)
      assert second_version.version_number == 2

      assert Repo.get!(ProjectTemplateVersion, first_version_id).checksum == first_version.checksum
      assert Repo.aggregate(ProjectTemplateVersion, :count) == 2
    end

    test "rejects updates to public templates from normal API" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Demo"})

      template =
        template
        |> Ecto.Changeset.change(%{visibility: "public", owner_id: nil})
        |> Repo.update!()

      assert {:error, :unauthorized} = ProjectTemplates.publish_new_version(scope, template, project)
    end
  end

  describe "template visibility" do
    test "lists own private templates and public templates only" do
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      owner_scope = AccountsFixtures.user_scope_fixture(owner)
      other_scope = AccountsFixtures.user_scope_fixture(other_user)
      owner_project = ProjectsFixtures.project_fixture(owner, %{name: "Owner Project"})
      other_project = ProjectsFixtures.project_fixture(other_user, %{name: "Other Project"})

      assert {:ok, own_template} =
               ProjectTemplates.create_template_from_project(owner_scope, owner_project, %{name: "My Template"})

      assert {:ok, public_template} =
               ProjectTemplates.create_template_from_project(other_scope, other_project, %{name: "Public Demo"})

      public_template =
        public_template
        |> Ecto.Changeset.change(%{visibility: "public", owner_id: nil})
        |> Repo.update!()

      visible_ids = other_scope |> ProjectTemplates.list_templates() |> Enum.map(& &1.id)

      refute own_template.id in visible_ids
      assert public_template.id in visible_ids
    end

    test "raises when fetching another user's private template" do
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      owner_scope = AccountsFixtures.user_scope_fixture(owner)
      other_scope = AccountsFixtures.user_scope_fixture(other_user)
      project = ProjectsFixtures.project_fixture(owner)

      assert {:ok, template} = ProjectTemplates.create_template_from_project(owner_scope, project, %{name: "Private"})

      assert_raise Ecto.NoResultsError, fn ->
        ProjectTemplates.get_template!(other_scope, template.id)
      end
    end
  end

  describe "instantiate_template/4" do
    test "creates a mutable project from a private template version and records the install" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      workspace = WorkspacesFixtures.workspace_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{workspace: workspace, name: "Source Project"})
      source_sheet = SheetsFixtures.sheet_fixture(project, %{name: "Hero"})
      source_asset = uploaded_image_asset(project, user, "template-avatar.png", "template-avatar")
      {:ok, _avatar} = Storyarn.Sheets.add_avatar(source_sheet, source_asset.id, %{name: "Default"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Starter"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert {:ok, cloned_project} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{name: "My Starter Copy"})

      assert cloned_project.name == "My Starter Copy"
      assert cloned_project.created_from_template_version_id == version.id
      assert cloned_project.id != project.id

      [cloned_sheet] = Storyarn.Sheets.list_all_sheets(cloned_project.id)
      [cloned_avatar] = Storyarn.Sheets.list_avatars(cloned_sheet.id)
      assert cloned_avatar.asset.project_id == cloned_project.id
      refute cloned_avatar.asset_id == source_asset.id
      assert {:ok, _binary} = Assets.storage_download(cloned_avatar.asset.key)
      on_exit(fn -> Assets.storage_delete(cloned_avatar.asset.key) end)

      install = Repo.one!(ProjectTemplateInstall)
      assert install.project_template_version_id == version.id
      assert install.user_id == user.id
      assert install.workspace_id == workspace.id
      assert install.project_id == cloned_project.id
    end

    test "allows any user to instantiate a public version" do
      owner = AccountsFixtures.user_fixture()
      installer = AccountsFixtures.user_fixture()
      owner_scope = AccountsFixtures.user_scope_fixture(owner)
      installer_scope = AccountsFixtures.user_scope_fixture(installer)
      source_project = ProjectsFixtures.project_fixture(owner, %{name: "Official Source"})
      installer_workspace = WorkspacesFixtures.workspace_fixture(installer)

      assert {:ok, template} =
               ProjectTemplates.create_template_from_project(owner_scope, source_project, %{name: "Official Demo"})

      public_template =
        template
        |> Ecto.Changeset.change(%{visibility: "public", owner_id: nil})
        |> Repo.update!()

      version = Repo.get!(ProjectTemplateVersion, public_template.current_version_id)

      assert {:ok, cloned_project} =
               ProjectTemplates.instantiate_template(installer_scope, version, installer_workspace, %{
                 name: "Public Copy"
               })

      assert cloned_project.owner_id == installer.id
      assert cloned_project.created_from_template_version_id == version.id
    end
  end

  describe "Audit.run/1" do
    test "detects a connection pointing to a soft-deleted node" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "dialogue")
      target_node = flow_node_fixture(flow, "hub")
      Repo.update!(FlowNode.soft_delete_changeset(target_node))

      flow_connection_fixture(flow, source_node, target_node)

      assert {:error, report} = Audit.run(project.id)
      assert [%{"type" => "stale_flow_connection"}] = report["errors"]
    end

    test "passes when a subflow exit pin can be remapped" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "subflow")
      target_node = flow_node_fixture(flow, "hub")

      flow_connection_fixture(flow, source_node, target_node, %{source_pin: "exit_#{target_node.id}"})

      assert {:ok, report} = Audit.run(project.id)
      assert report["status"] == "passed"
    end

    test "detects a subflow exit pin that cannot be remapped" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "subflow")
      target_node = flow_node_fixture(flow, "hub")

      flow_connection_fixture(flow, source_node, target_node, %{source_pin: "exit_999999"})

      assert {:error, report} = Audit.run(project.id)
      assert [%{"type" => "unremappable_subflow_exit_pin", "source_pin" => "exit_999999"}] = report["errors"]
    end

    test "detects scene pin refs to soft-deleted sheets and flows" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      scene = ScenesFixtures.scene_fixture(project)
      sheet = SheetsFixtures.sheet_fixture(project)
      flow = FlowsFixtures.flow_fixture(project)

      _sheet_pin = ScenesFixtures.pin_fixture(scene, %{"sheet_id" => sheet.id})
      _flow_pin = ScenesFixtures.pin_fixture(scene, %{"flow_id" => flow.id})

      Repo.update!(Sheet.delete_changeset(sheet))
      Repo.update!(Flow.delete_changeset(flow))

      assert {:error, report} = Audit.run(project.id)
      error_types = Enum.map(report["errors"], & &1["type"])

      assert "invalid_scene_pin_sheet_ref" in error_types
      assert "invalid_scene_pin_flow_ref" in error_types
    end

    test "detects scene zone targets pointing to soft-deleted scenes and flows" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      scene = ScenesFixtures.scene_fixture(project)
      target_scene = ScenesFixtures.scene_fixture(project)
      target_flow = FlowsFixtures.flow_fixture(project)

      _scene_zone =
        ScenesFixtures.zone_fixture(scene, %{
          "target_type" => "scene",
          "target_id" => target_scene.id
        })

      _flow_zone =
        ScenesFixtures.zone_fixture(scene, %{
          "target_type" => "flow",
          "target_id" => target_flow.id
        })

      Repo.update!(Scene.delete_changeset(target_scene))
      Repo.update!(Flow.delete_changeset(target_flow))

      assert {:error, report} = Audit.run(project.id)
      target_types = Enum.map(report["errors"], & &1["target_type"])

      assert Enum.all?(report["errors"], &(&1["type"] == "invalid_scene_zone_target_ref"))
      assert "scene" in target_types
      assert "flow" in target_types
    end

    test "detects referenced assets without a copyable blob" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      scene = ScenesFixtures.scene_fixture(project)
      flow = flow_fixture(project)
      asset = AssetsFixtures.image_asset_fixture(project, user)

      {:ok, _scene} = Storyarn.Scenes.update_scene(scene, %{"background_asset_id" => asset.id})
      node = flow_node_fixture(flow, "dialogue")
      Storyarn.Flows.update_node(node, %{data: %{"audio_asset_id" => asset.id}})

      assert {:error, report} = Audit.run(project.id)

      assert Enum.any?(report["errors"], fn error ->
               error["type"] == "uncopiable_asset_reference" and
                 error["field"] == "background_asset_id" and
                 error["asset_id"] == asset.id and
                 error["has_blob_hash"] == false
             end)

      assert Enum.any?(report["errors"], fn error ->
               error["type"] == "uncopiable_asset_reference" and
                 error["field"] == "data.audio_asset_id" and
                 error["asset_id"] == asset.id
             end)
    end
  end

  defp flow_fixture(project) do
    %Flow{project_id: project.id}
    |> Flow.create_changeset(%{name: "Main Flow", shortcut: "main-flow"})
    |> Repo.insert!()
  end

  defp flow_node_fixture(flow, type) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(%{type: type, position_x: 0.0, position_y: 0.0})
    |> Repo.insert!()
  end

  defp flow_connection_fixture(flow, source_node, target_node, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_pin: "out",
          target_pin: "in"
        },
        attrs
      )

    %FlowConnection{flow_id: flow.id}
    |> FlowConnection.create_changeset(
      Map.merge(attrs, %{source_node_id: source_node.id, target_node_id: target_node.id})
    )
    |> Repo.insert!()
  end

  defp uploaded_image_asset(project, user, filename, content) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "image/png"},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(BlobStore.blob_key(project.id, asset.blob_hash, "png"))
    end)

    asset
  end
end
