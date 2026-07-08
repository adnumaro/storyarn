defmodule Storyarn.ProjectTemplates.PortableTest do
  use Storyarn.DataCase, async: false

  alias Mix.Tasks.Storyarn.Templates.Export, as: ExportTask
  alias Mix.Tasks.Storyarn.Templates.Import, as: ImportTask
  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectsFixtures
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.SheetsFixtures
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.WorkspacesFixtures

  describe "portable template bundles" do
    test "exports an audited bundle with referenced asset blobs" do
      %{project: project, asset: asset} = portable_source_project()
      output_path = bundle_path()

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, %{manifest: manifest, path: ^output_path}} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Veilbreak Demo",
                 slug: "veilbreak-demo",
                 description: "Local demo export",
                 version_notes: "Initial portable version"
               )

      assert manifest["template"]["name"] == "Veilbreak Demo"
      assert manifest["template"]["slug"] == "veilbreak-demo"
      assert manifest["asset_count"] == 1
      assert manifest["checksum"] =~ ~r/^[a-f0-9]{64}$/

      assert {:ok, bundle} = PortableBundle.read(output_path)
      assert bundle.manifest == manifest

      assert [blob] = bundle.manifest["asset_blobs"]
      assert blob["asset_id"] == asset.id
      assert blob["sha256"] == asset.blob_hash
      assert byte_size(bundle.files[blob["path"]]) == blob["size"]

      assert {:ok, ^manifest} = ProjectTemplates.preview_portable_template(output_path)
    end

    test "imports a public bundle and instantiates a mutable project with copied assets" do
      %{project: project, asset: source_asset} = portable_source_project()
      output_path = bundle_path()
      installer = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(installer)
      workspace = WorkspacesFixtures.workspace_fixture(installer)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Veilbreak Demo",
                 slug: "veilbreak-demo"
               )

      private_template = private_template_with_slug!("veilbreak-demo")

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 slug: "veilbreak-demo",
                 name: "Veilbreak Demo",
                 verify_user_id: installer.id,
                 verify_workspace_id: workspace.id
               )

      assert template.visibility == "public"
      assert is_nil(template.owner_id)
      refute template.id == private_template.id

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)
      assert version.audit_report["import_materialization"]["status"] == "passed"

      assert {:ok, imported_snapshot} = SnapshotStorage.load_snapshot(version.snapshot_storage_key)
      assert {:ok, imported_asset_manifest} = SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      assert inspect(imported_snapshot) =~ "project_templates/imported_blobs/veilbreak-demo/"
      refute inspect(imported_snapshot) =~ source_asset.key

      assert [imported_asset] = imported_asset_manifest["assets"]
      assert imported_asset["blob_hash"] == source_asset.blob_hash
      assert imported_asset["key"] =~ "project_templates/imported_blobs/veilbreak-demo/"
      refute imported_asset["key"] == source_asset.key
      on_exit(fn -> Assets.storage_delete(imported_asset["key"]) end)

      assert {:ok, cloned_project} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{
                 name: "Installed Veilbreak"
               })

      assert cloned_project.name == "Installed Veilbreak"
      assert cloned_project.created_from_template_version_id == version.id

      [cloned_asset] = Assets.list_assets(cloned_project.id)
      assert cloned_asset.project_id == cloned_project.id
      assert cloned_asset.blob_hash == source_asset.blob_hash
      refute cloned_asset.id == source_asset.id
      refute cloned_asset.key == source_asset.key
      assert {:ok, _binary} = Assets.storage_download(cloned_asset.key)
      on_exit(fn -> Assets.storage_delete(cloned_asset.key) end)
    end

    test "rejects a bundle whose checksum does not match the payload" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      tampered_path = bundle_path()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(tampered_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)

      tampered_snapshot = put_in(bundle.snapshot, ["project", "name"], "Tampered Project")

      assert {:ok, _path} =
               PortableBundle.write(
                 tampered_path,
                 bundle.manifest,
                 tampered_snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      assert {:error, :bundle_checksum_mismatch} = ProjectTemplates.preview_portable_template(tampered_path)
    end

    test "rejects a bundle without a source audit report" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      incomplete_path = bundle_path()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(incomplete_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)

      assert {:ok, _path} =
               PortableBundle.write(
                 incomplete_path,
                 Map.delete(bundle.manifest, "audit_report"),
                 bundle.snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      assert {:error, :invalid_bundle_manifest} = ProjectTemplates.preview_portable_template(incomplete_path)
    end

    test "rejects a bundle with unsafe tar entries" do
      path = bundle_path()
      on_exit(fn -> File.rm(path) end)

      assert :ok = :erl_tar.create(String.to_charlist(path), [{~c"../evil", "bad"}], [:compressed])

      assert {:error, {:unsafe_bundle_path, "../evil"}} = PortableBundle.read(path)
    end

    test "rejects import when a referenced asset blob is missing from the bundle" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      missing_blob_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(missing_blob_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)
      assert [blob] = bundle.manifest["asset_blobs"]
      blob_path = blob["path"]

      assert {:ok, _path} =
               PortableBundle.write(missing_blob_path, bundle.manifest, bundle.snapshot, bundle.asset_manifest, [])

      assert {:error, {:missing_asset_blob, ^blob_path}} =
               ProjectTemplates.import_portable_template(missing_blob_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )
    end

    test "rejects import when the snapshot cannot be materialized locally" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      incompatible_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(incompatible_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)

      incompatible_snapshot = put_in(bundle.snapshot, ["project", "project_type"], "unsupported")

      manifest =
        put_in(
          bundle.manifest,
          ["checksum"],
          PortableBundle.checksum(incompatible_snapshot, bundle.asset_manifest, bundle.manifest["asset_blobs"])
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 incompatible_path,
                 manifest,
                 incompatible_snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      assert {:error, {:template_materialization_failed, report}} =
               ProjectTemplates.import_portable_template(incompatible_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert report["status"] == "failed"
    end

    test "rejects import without a materialization verification scope" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)

      assert {:error, :template_import_requires_materialization_scope} =
               ProjectTemplates.import_portable_template(output_path, visibility: "public")
    end

    test "rejects private import without owner_id" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)

      assert {:error, :private_template_requires_owner_id} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "private",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )
    end

    test "rejects invalid visibility before uploading artifacts" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)

      assert {:error, {:invalid_visibility, "shared"}} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "shared",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )
    end

    test "rejects public slug conflicts unless update_existing is explicit" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()
      _existing = public_template_with_slug!("veilbreak-demo")

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Veilbreak Demo",
                 slug: "veilbreak-demo"
               )

      assert {:error, {:template_slug_exists, "veilbreak-demo"}} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )
    end

    test "rejects export for a soft-deleted project" do
      %{project: project, user: user} = portable_source_project()
      output_path = bundle_path()

      on_exit(fn -> File.rm(output_path) end)

      project
      |> Project.soft_delete_changeset(%{deleted_at: DateTime.utc_now(:second), deleted_by_id: user.id})
      |> Repo.update!()

      assert {:error, :project_deleted} = ProjectTemplates.export_portable_template(project.id, output_path)
    end

    test "mix tasks reject invalid flags" do
      assert_raise OptionParser.ParseError, fn ->
        ImportTask.run(["bundle.tar.gz", "--visibilty", "public"])
      end

      assert_raise OptionParser.ParseError, fn ->
        ExportTask.run(["1", "--ouptut", "bundle.tar.gz"])
      end
    end
  end

  defp portable_source_project do
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(user, %{name: "Veilbreak Local"})
    sheet = SheetsFixtures.sheet_fixture(project, %{name: "Hero"})
    asset = uploaded_image_asset(project, user, "hero-avatar.png", "portable-avatar")

    {:ok, _avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "Default"})

    %{project: project, user: user, asset: asset}
  end

  defp uploaded_image_asset(project, user, filename, content) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "image/png", metadata: %{}, skip_variants: true},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(BlobStore.blob_key(project.id, asset.blob_hash, "png"))
    end)

    asset
  end

  defp private_template_with_slug!(slug) do
    owner = AccountsFixtures.user_fixture()

    %ProjectTemplate{owner_id: owner.id}
    |> ProjectTemplate.create_changeset(%{
      "name" => "Private Veilbreak",
      "slug" => slug,
      "visibility" => "private",
      "status" => "active"
    })
    |> Repo.insert!()
  end

  defp public_template_with_slug!(slug) do
    %ProjectTemplate{}
    |> ProjectTemplate.create_changeset(%{
      "name" => "Public Veilbreak",
      "slug" => slug,
      "visibility" => "public",
      "status" => "active"
    })
    |> Repo.insert!()
  end

  defp verification_scope do
    user = AccountsFixtures.user_fixture()
    workspace = WorkspacesFixtures.workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  defp asset_files(bundle) do
    Enum.map(bundle.manifest["asset_blobs"], fn blob ->
      {blob["path"], bundle.files[blob["path"]]}
    end)
  end

  defp bundle_path do
    Path.join(System.tmp_dir!(), "storyarn-template-#{System.unique_integer([:positive])}.tar.gz")
  end

  defp register_template_artifact_cleanup(version) do
    on_exit(fn ->
      Assets.storage_delete(version.snapshot_storage_key)
      Assets.storage_delete(version.asset_manifest_storage_key)
    end)
  end
end
