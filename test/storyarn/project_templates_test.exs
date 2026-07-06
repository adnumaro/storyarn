defmodule Storyarn.ProjectTemplatesTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.AssetsFixtures
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.FlowsFixtures
  alias Storyarn.Localization
  alias Storyarn.LocalizationFixtures
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectsFixtures
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.ScenesFixtures
  alias Storyarn.Sheets.Sheet
  alias Storyarn.SheetsFixtures
  alias Storyarn.Workers.PublishProjectTemplateWorker
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

      publication =
        Repo.get_by!(ProjectTemplatePublication,
          project_template_id: template.id,
          project_template_version_id: version.id
        )

      assert version.project_template_id == template.id
      assert version.version_number == 1
      assert version.source_project_id == project.id
      assert version.snapshot_storage_key == publication.snapshot_storage_key
      assert version.asset_manifest_storage_key == publication.asset_manifest_storage_key
      assert version.snapshot_storage_key =~ "project_template_publications/#{publication.id}/snapshot-"
      assert version.asset_manifest_storage_key =~ "project_template_publications/#{publication.id}/asset-manifest-"
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

  describe "request_template_publication/3" do
    test "creates a queued publication and enqueues a worker" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Queued Source"})

      assert {:ok, publication} =
               ProjectTemplates.request_template_publication(scope, project, %{
                 name: "Queued Starter",
                 description: "Queued description"
               })

      assert publication.owner_id == user.id
      assert publication.requested_by_id == user.id
      assert publication.source_project_id == project.id
      assert publication.mode == "new"
      assert publication.status == "queued"
      assert publication.name == "Queued Starter"
      assert publication.oban_job_id

      assert_enqueued(
        worker: PublishProjectTemplateWorker,
        args: %{"publication_id" => publication.id}
      )
    end

    test "rejects another active new publication for the same project and owner" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)

      assert {:ok, _publication} = ProjectTemplates.request_template_publication(scope, project, %{name: "First"})

      assert {:error, :publication_already_active} =
               ProjectTemplates.request_template_publication(scope, project, %{name: "Second"})
    end

    test "does not allow public visibility through queued publication API" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)

      assert {:error, :public_visibility_requires_admin} =
               ProjectTemplates.request_template_publication(scope, project, %{
                 name: "Official Demo",
                 visibility: "public"
               })
    end
  end

  describe "perform_template_publication/2" do
    test "publishes a queued new template" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Worker Source"})

      assert {:ok, publication} =
               ProjectTemplates.request_template_publication(scope, project, %{name: "Worker Starter"})

      assert {:ok, published} = ProjectTemplates.perform_template_publication(publication.id)

      assert published.status == "published"
      assert published.project_template_id
      assert published.project_template_version_id
      assert published.snapshot_storage_key =~ "project_template_publications/#{publication.id}/snapshot-"

      template = ProjectTemplates.get_template!(scope, published.project_template_id)
      version = Repo.get!(ProjectTemplateVersion, published.project_template_version_id)

      assert template.name == "Worker Starter"
      assert template.current_version_id == version.id
      assert version.version_number == 1
    end

    test "fails without creating a template when audit fails" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Broken Source"})
      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "dialogue")
      target_node = flow_node_fixture(flow, "hub")

      Repo.update!(FlowNode.soft_delete_changeset(target_node))
      flow_connection_fixture(flow, source_node, target_node)

      assert {:ok, publication} =
               ProjectTemplates.request_template_publication(scope, project, %{name: "Broken Starter"})

      assert {:ok, failed} = ProjectTemplates.perform_template_publication(publication.id)

      assert failed.status == "failed"
      assert failed.error_code == "audit_failed"
      refute failed.project_template_id
      assert Repo.aggregate(ProjectTemplatePublication, :count) == 1
      assert ProjectTemplates.list_templates(scope, source_project_id: project.id) == []
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

      versions = ProjectTemplates.list_template_versions(scope, updated_template)
      assert Enum.map(versions, & &1.version_number) == [2, 1]
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

    test "rejects publishing from a project that does not match the template source" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Original Source"})
      other_project = ProjectsFixtures.project_fixture(user, %{name: "Other Source"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Template"})

      assert {:error, :invalid_source_project} =
               ProjectTemplates.publish_new_version(scope, template, other_project)
    end
  end

  describe "update_template/3" do
    test "updates mutable metadata for an owned private template" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Source"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Starter"})

      assert {:ok, updated_template} =
               ProjectTemplates.update_template(scope, template, %{
                 name: "Updated Starter",
                 description: "Updated description"
               })

      assert updated_template.id == template.id
      assert updated_template.name == "Updated Starter"
      assert updated_template.description == "Updated description"
      assert updated_template.current_version_id == template.current_version_id
    end

    test "rejects metadata updates from another user" do
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      owner_scope = AccountsFixtures.user_scope_fixture(owner)
      other_scope = AccountsFixtures.user_scope_fixture(other_user)
      project = ProjectsFixtures.project_fixture(owner)

      assert {:ok, template} = ProjectTemplates.create_template_from_project(owner_scope, project, %{name: "Private"})

      assert {:error, :unauthorized} =
               ProjectTemplates.update_template(other_scope, template, %{name: "Taken"})
    end
  end

  describe "update_template_and_publish_new_version/4" do
    test "updates metadata and publishes a version atomically" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Atomic Source"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Starter"})

      assert {:ok, updated_template} =
               ProjectTemplates.update_template_and_publish_new_version(scope, template, project, %{
                 name: "Starter Updated",
                 description: "Published atomically"
               })

      version = Repo.get!(ProjectTemplateVersion, updated_template.current_version_id)

      assert updated_template.name == "Starter Updated"
      assert updated_template.description == "Published atomically"
      assert version.version_number == 2
      assert Repo.aggregate(ProjectTemplateVersion, :count) == 2
    end

    test "does not update metadata when publication audit fails" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{name: "Audit Source"})

      assert {:ok, template} =
               ProjectTemplates.create_template_from_project(scope, project, %{
                 name: "Stable Starter",
                 description: "Original"
               })

      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "dialogue")
      target_node = flow_node_fixture(flow, "hub")
      Repo.update!(FlowNode.soft_delete_changeset(target_node))
      flow_connection_fixture(flow, source_node, target_node)

      assert {:error, report} =
               ProjectTemplates.update_template_and_publish_new_version(scope, template, project, %{
                 name: "Should Not Persist",
                 description: "Should not persist"
               })

      assert report["status"] == "failed"

      unchanged_template = Repo.get!(Storyarn.ProjectTemplates.ProjectTemplate, template.id)
      assert unchanged_template.name == "Stable Starter"
      assert unchanged_template.description == "Original"
      assert unchanged_template.current_version_id == template.current_version_id
      assert Repo.aggregate(ProjectTemplateVersion, :count) == 1
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

      assert {:error, :not_found} = ProjectTemplates.get_template(other_scope, template.id)
    end

    test "does not fetch archived templates through the visible API" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Archived"})

      template
      |> Ecto.Changeset.change(%{status: "archived"})
      |> Repo.update!()

      assert_raise Ecto.NoResultsError, fn ->
        ProjectTemplates.get_template!(scope, template.id)
      end

      assert {:error, :not_found} = ProjectTemplates.get_template(scope, template.id)
    end
  end

  describe "instantiate_template/4" do
    test "creates a mutable project from a private template version and records the install" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      workspace = WorkspacesFixtures.workspace_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{workspace: workspace, name: "Source Project"})
      source_sheet = SheetsFixtures.sheet_fixture(project, %{name: "Hero"})
      source_block = SheetsFixtures.block_fixture(source_sheet, %{config: %{"label" => "Bio"}})
      source_asset = uploaded_image_asset(project, user, "template-avatar.png", "template-avatar")
      {:ok, _avatar} = Storyarn.Sheets.add_avatar(source_sheet, source_asset.id, %{name: "Default"})
      LocalizationFixtures.language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _localized_block =
        LocalizationFixtures.localized_text_fixture(project.id, %{
          source_type: "block",
          source_id: source_block.id,
          source_field: "value.content",
          source_text: "Hero biography",
          locale_code: "es"
        })

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Starter"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert {:ok, cloned_project} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{name: "My Starter Copy"})

      assert cloned_project.name == "My Starter Copy"
      assert cloned_project.created_from_template_version_id == version.id
      assert cloned_project.id != project.id

      [cloned_sheet] = Storyarn.Sheets.list_all_sheets(cloned_project.id)
      [cloned_block] = Storyarn.Sheets.list_blocks(cloned_sheet.id)
      [cloned_text] = Localization.list_texts_for_export(cloned_project.id, ["es"])

      assert cloned_text.source_type == "block"
      assert cloned_text.source_id == cloned_block.id
      refute cloned_text.source_id == source_block.id

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

    test "rejects archived template versions" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      workspace = WorkspacesFixtures.workspace_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{workspace: workspace, name: "Archived Source"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Archived Starter"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      template
      |> Ecto.Changeset.change(%{status: "archived"})
      |> Repo.update!()

      assert {:error, :archived} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{name: "Archived Copy"})
    end

    test "rejects tampered template artifacts before creating a project" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      workspace = WorkspacesFixtures.workspace_fixture(user)
      project = ProjectsFixtures.project_fixture(user, %{workspace: workspace, name: "Checksum Source"})

      assert {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Checksum Starter"})

      version =
        ProjectTemplateVersion
        |> Repo.get!(template.current_version_id)
        |> Ecto.Changeset.change(checksum: String.duplicate("0", 64))
        |> Repo.update!()

      project_count = Repo.aggregate(Project, :count)

      assert {:error, :checksum_mismatch} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{name: "Tampered Copy"})

      assert Repo.aggregate(Project, :count) == project_count
    end

    test "rolls back the recovered project when install bookkeeping fails" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      workspace = WorkspacesFixtures.workspace_fixture(user)
      source_project = ProjectsFixtures.project_fixture(user, %{workspace: workspace, name: "Rollback Source"})
      _sheet = SheetsFixtures.sheet_fixture(source_project)

      assert {:ok, template} =
               ProjectTemplates.create_template_from_project(scope, source_project, %{name: "Rollback Starter"})

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      Repo.delete!(version)

      project_count = Repo.aggregate(Project, :count)
      install_count = Repo.aggregate(ProjectTemplateInstall, :count)

      assert {:error, %Ecto.Changeset{} = changeset} =
               ProjectTemplates.instantiate_template(scope, %{version | project_template: template}, workspace, %{
                 name: "Should Roll Back"
               })

      refute changeset.valid?
      assert Repo.aggregate(Project, :count) == project_count
      assert Repo.aggregate(ProjectTemplateInstall, :count) == install_count
    end
  end

  describe "Audit.run/1" do
    test "materializes a valid project in rollback and compares counts" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      sheet = SheetsFixtures.sheet_fixture(project)
      _block = SheetsFixtures.block_fixture(sheet)

      flow = flow_fixture(project)
      source_node = flow_node_fixture(flow, "dialogue")
      target_node = flow_node_fixture(flow, "hub")
      flow_connection_fixture(flow, source_node, target_node)

      scene = ScenesFixtures.scene_fixture(project)
      layer = ScenesFixtures.layer_fixture(scene)
      _pin = ScenesFixtures.pin_fixture(scene, %{"layer_id" => layer.id})
      _zone = ScenesFixtures.zone_fixture(scene, %{"layer_id" => layer.id})

      project_count = Repo.aggregate(Project, :count)

      assert {:ok, report} = Audit.run(project.id)
      assert report["materialization"]["status"] == "passed"
      assert report["materialization"]["source_counts"] == report["materialization"]["snapshot_counts"]
      assert report["materialization"]["snapshot_counts"] == report["materialization"]["recovered_counts"]
      assert Repo.aggregate(Project, :count) == project_count
    end

    test "removes copied asset files created during rollback materialization" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      sheet = SheetsFixtures.sheet_fixture(project)
      avatar_asset = uploaded_image_asset(project, user, "rollback-avatar.png", "rollback-avatar")
      {:ok, _avatar} = Storyarn.Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Hero"})

      storage_files_before_audit = storage_files()

      assert {:ok, report} = Audit.run(project.id)
      assert report["materialization"]["status"] == "passed"
      assert storage_files() == storage_files_before_audit
    end

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

    test "detects localization refs that cannot be remapped" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      LocalizationFixtures.language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _text =
        LocalizationFixtures.localized_text_fixture(project.id, %{
          source_type: "block",
          source_id: System.unique_integer([:positive]),
          source_field: "value.content",
          source_text: "Missing block",
          locale_code: "es"
        })

      assert {:error, report} = Audit.run(project.id)

      assert Enum.any?(report["errors"], fn error ->
               error["type"] == "invalid_localization_source_ref" and
                 error["source_type"] == "block"
             end)
    end

    test "passes when localization voice assets are copied during materialization" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user)
      flow = flow_fixture(project)
      node = flow_node_fixture(flow, "dialogue")
      voice_asset = uploaded_audio_asset(project, user, "line.mp3", "voice-over")

      LocalizationFixtures.language_fixture(project, %{locale_code: "es", name: "Spanish"})

      text =
        LocalizationFixtures.localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: node.id,
          source_field: "text",
          locale_code: "es"
        })

      assert {:ok, _text} = Localization.update_text(text, %{vo_asset_id: voice_asset.id, vo_status: "recorded"})

      assert {:ok, report} = Audit.run(project.id)
      assert report["materialization"]["status"] == "passed"
      refute Enum.any?(report["errors"], &(&1["field"] == "vo_asset_id"))
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

  defp uploaded_audio_asset(project, user, filename, content) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "audio/mpeg"},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(BlobStore.blob_key(project.id, asset.blob_hash, "mp3"))
    end)

    asset
  end

  defp storage_files do
    upload_dir =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.get(:upload_dir, "priv/static/uploads/test")
      |> Path.expand()

    if File.dir?(upload_dir) do
      upload_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, upload_dir))
      |> Enum.sort()
    else
      []
    end
  end
end
