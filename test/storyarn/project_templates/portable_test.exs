defmodule Storyarn.ProjectTemplates.PortableTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Mix.Tasks.Storyarn.Templates.Export, as: ExportTask
  alias Mix.Tasks.Storyarn.Templates.Import, as: ImportTask
  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows
  alias Storyarn.FlowsFixtures
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectsFixtures
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.Audit
  alias Storyarn.ProjectTemplates.PortableBundle
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.SheetsFixtures
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker
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
      installer = AccountsFixtures.set_super_admin(AccountsFixtures.user_fixture())

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
      assert %Project{id: source_project_id} = template.source_project
      assert template.source_project_id == source_project_id
      assert template.source_project.owner_id == installer.id
      assert is_nil(template.source_project.created_from_template_version_id)
      assert ProjectTemplates.can_manage_template?(scope, template)
      register_project_asset_cleanup(template.source_project)

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)
      assert version.source_project_id == source_project_id
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

    test "uploads a duplicate content hash only once while validating every bundle entry" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      duplicate_path = bundle_path()
      installer = AccountsFixtures.set_super_admin(AccountsFixtures.user_fixture())
      workspace = WorkspacesFixtures.workspace_fixture(installer)

      on_exit(fn ->
        File.rm(output_path)
        File.rm(duplicate_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Duplicate Hash Import",
                 slug: "duplicate-hash-import"
               )

      assert {:ok, bundle} = PortableBundle.read(output_path)
      [blob] = bundle.manifest["asset_blobs"]
      data = bundle.files[blob["path"]]

      duplicate_blob =
        blob
        |> Map.put("asset_id", blob["asset_id"] + 1)
        |> Map.put("filename", "duplicate.png")
        |> Map.put("path", "assets/#{blob["sha256"]}/duplicate.png")

      blobs = [blob, duplicate_blob]

      manifest =
        bundle.manifest
        |> Map.put("asset_count", 2)
        |> Map.put("asset_blobs", blobs)
        |> Map.put(
          "checksum",
          PortableBundle.checksum(bundle.snapshot, bundle.asset_manifest, blobs)
        )

      assert {:ok, ^duplicate_path} =
               PortableBundle.write(
                 duplicate_path,
                 manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 [{blob["path"], data}, {duplicate_blob["path"], data}]
               )

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(duplicate_path,
                 visibility: "public",
                 verify_user_id: installer.id,
                 verify_workspace_id: workspace.id
               )

      register_project_asset_cleanup(template.source_project)
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)

      assert {:ok, %{"assets" => [%{"key" => imported_blob_key}]}} =
               SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      on_exit(fn -> Assets.storage_delete(imported_blob_key) end)

      duplicate_key = Path.join(Path.dirname(imported_blob_key), "duplicate.png")
      refute imported_blob_key == duplicate_key
      assert {:error, :enoent} = Assets.storage_download(duplicate_key)
    end

    test "rejects duplicate content hashes with different content types" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      incompatible_path = bundle_path()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(incompatible_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Duplicate MIME Import",
                 slug: "duplicate-mime-import"
               )

      assert {:ok, bundle} = PortableBundle.read(output_path)
      [blob] = bundle.manifest["asset_blobs"]

      duplicate_blob =
        blob
        |> Map.put("asset_id", blob["asset_id"] + 1)
        |> Map.put("content_type", "image/jpeg")
        |> Map.put("filename", "duplicate.jpg")
        |> Map.put("path", "assets/#{blob["sha256"]}/duplicate.jpg")

      blobs = [blob, duplicate_blob]

      manifest =
        bundle.manifest
        |> Map.put("asset_count", 2)
        |> Map.put("asset_blobs", blobs)
        |> Map.put(
          "checksum",
          PortableBundle.checksum(bundle.snapshot, bundle.asset_manifest, blobs)
        )

      assert {:ok, ^incompatible_path} =
               PortableBundle.write(
                 incompatible_path,
                 manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 [
                   {blob["path"], bundle.files[blob["path"]]},
                   {duplicate_blob["path"], bundle.files[blob["path"]]}
                 ]
               )

      assert {:error, {:duplicate_asset_content_type_mismatch, hash, original_content_type, "image/jpeg"}} =
               ProjectTemplates.preview_portable_template(incompatible_path)

      assert hash == blob["sha256"]
      assert original_content_type == blob["content_type"]
    end

    test "rejects malformed asset metadata before uploading bundle blobs" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      malformed_path = bundle_path()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(malformed_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path, slug: "malformed-asset-metadata")

      assert {:ok, bundle} = PortableBundle.read(output_path)
      [blob] = bundle.manifest["asset_blobs"]
      malformed_blobs = [Map.put(blob, "filename", %{"unexpected" => "object"})]

      manifest =
        bundle.manifest
        |> Map.put("asset_blobs", malformed_blobs)
        |> Map.put(
          "checksum",
          PortableBundle.checksum(
            bundle.snapshot,
            bundle.asset_manifest,
            malformed_blobs
          )
        )

      assert {:ok, ^malformed_path} =
               PortableBundle.write(
                 malformed_path,
                 manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      assert {:error, :invalid_bundle_manifest} =
               ProjectTemplates.preview_portable_template(malformed_path)

      assert imported_blob_files("malformed-asset-metadata") == []
    end

    test "imports an editable source and publishes version 2 on the same private template" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      editor = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(editor)
      workspace = WorkspacesFixtures.workspace_fixture(editor)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Editable Veilbreak",
                 slug: "editable-veilbreak"
               )

      assert {:ok, imported_template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "private",
                 owner_id: editor.id,
                 verify_user_id: editor.id,
                 verify_workspace_id: workspace.id
               )

      source_project = imported_template.source_project
      assert %Project{} = source_project
      assert source_project.owner_id == editor.id
      assert is_nil(source_project.created_from_template_version_id)
      register_project_asset_cleanup(source_project)

      version_1 = Repo.get!(ProjectTemplateVersion, imported_template.current_version_id)
      register_template_artifact_cleanup(version_1)
      assert version_1.source_project_id == source_project.id

      assert {:ok, republished_template} =
               ProjectTemplates.publish_new_version(
                 scope,
                 imported_template,
                 source_project
               )

      assert republished_template.id == imported_template.id
      refute republished_template.current_version_id == version_1.id

      version_2 = Repo.get!(ProjectTemplateVersion, republished_template.current_version_id)
      register_template_artifact_cleanup(version_2)
      assert version_2.version_number == 2
      assert version_2.source_project_id == source_project.id
    end

    test "deleting an imported template also garbage-collects its imported blobs" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      editor = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(editor)
      workspace = WorkspacesFixtures.workspace_fixture(editor)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Disposable Import",
                 slug: "disposable-import"
               )

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "private",
                 owner_id: editor.id,
                 verify_user_id: editor.id,
                 verify_workspace_id: workspace.id
               )

      register_project_asset_cleanup(template.source_project)
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert {:ok, %{"assets" => [%{"key" => imported_blob_key}]}} =
               SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      on_exit(fn -> Assets.storage_delete(imported_blob_key) end)

      assert {:ok, archived} = ProjectTemplates.archive_template(scope, template)
      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, archived)

      assert [job] = all_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
      assert imported_blob_key in job.args["storage_keys"]
      assert :ok = perform_job(DeleteProjectTemplateArtifactsWorker, job.args)
      assert {:error, :enoent} = Assets.storage_download(imported_blob_key)
    end

    test "refuses to delete an imported template with a non-canonical blob key" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      editor = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(editor)
      workspace = WorkspacesFixtures.workspace_fixture(editor)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Disposable Import",
                 slug: "disposable-import"
               )

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "private",
                 owner_id: editor.id,
                 verify_user_id: editor.id,
                 verify_workspace_id: workspace.id
               )

      register_project_asset_cleanup(template.source_project)

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert {:ok, %{"assets" => [%{"key" => imported_blob_key}]} = asset_manifest} =
               SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      on_exit(fn -> Assets.storage_delete(imported_blob_key) end)

      ["project_templates", "imported_blobs", slug, suffix, _hash, _filename] =
        String.split(imported_blob_key, "/")

      malformed_key =
        "project_templates/imported_blobs/#{slug}/#{suffix}/not-a-sha256/unrelated.png"

      tampered_manifest =
        Map.update!(asset_manifest, "assets", fn assets ->
          [%{"key" => malformed_key} | assets]
        end)

      assert {:ok, _size_bytes} =
               SnapshotStorage.store_raw(version.asset_manifest_storage_key, tampered_manifest)

      assert {:ok, _url} =
               Assets.storage_upload(malformed_key, "unrelated", "application/octet-stream")

      on_exit(fn -> Assets.storage_delete(malformed_key) end)

      assert {:ok, archived} = ProjectTemplates.archive_template(scope, template)
      manifest_key = version.asset_manifest_storage_key

      assert {:error, {:template_asset_manifest_unreadable, ^manifest_key, :invalid_asset_manifest}} =
               ProjectTemplates.delete_template(scope, archived)

      assert Repo.get(ProjectTemplate, template.id)
      assert Repo.get(ProjectTemplateVersion, version.id)
      assert all_enqueued(worker: DeleteProjectTemplateArtifactsWorker) == []
      assert {:ok, _contents} = Assets.storage_download(imported_blob_key)
      assert {:ok, "unrelated"} = Assets.storage_download(malformed_key)
    end

    test "repairs a homogeneous legacy sequence bundle through preview, import, and installation" do
      %{project: project} = portable_source_project()
      flow = FlowsFixtures.flow_fixture(project)
      {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Legacy sequence"})
      output_path = bundle_path()
      legacy_path = bundle_path()
      installer = AccountsFixtures.set_super_admin(AccountsFixtures.user_fixture())
      scope = AccountsFixtures.user_scope_fixture(installer)
      workspace = WorkspacesFixtures.workspace_fixture(installer)

      on_exit(fn ->
        File.rm(output_path)
        File.rm(legacy_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Legacy Sequence Demo",
                 slug: "legacy-sequence-demo"
               )

      assert {:ok, bundle} = PortableBundle.read(output_path)
      legacy_snapshot = homogeneous_legacy_sequence_snapshot(bundle.snapshot)

      forged_repair_report = %{
        "status" => "repaired_with_warnings",
        "strategy" => "forged",
        "repaired_sequence_count" => 999,
        "repaired_sequences" => [],
        "localization" => %{"removed_count" => 999},
        "warning" => "FORGED REPAIR REPORT"
      }

      legacy_manifest =
        bundle.manifest
        |> put_in(
          ["checksum"],
          PortableBundle.checksum(
            legacy_snapshot,
            bundle.asset_manifest,
            bundle.manifest["asset_blobs"]
          )
        )
        |> Map.put("legacy_snapshot_repair", forged_repair_report)

      assert {:ok, ^legacy_path} =
               PortableBundle.write(
                 legacy_path,
                 legacy_manifest,
                 legacy_snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      assert {:ok, preview} =
               ProjectTemplates.preview_portable_template(legacy_path,
                 repair_legacy_snapshot: true
               )

      repair_preview = preview["legacy_snapshot_repair"]
      assert repair_preview["status"] == "repaired_with_warnings"
      assert repair_preview["strategy"] == "replace_missing_sequences_with_annotations"
      assert repair_preview["repaired_sequence_count"] == 1
      assert repair_preview["warning"] =~ "Missing sequence grouping, tracks, and visual layers"
      refute repair_preview == forged_repair_report
      refute repair_preview["warning"] =~ "FORGED"

      assert [
               %{
                 "flow_id" => flow_id,
                 "node_id" => node_id
               }
             ] = repair_preview["repaired_sequences"]

      assert flow_id == flow.id
      assert node_id == sequence.id

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(legacy_path,
                 visibility: "public",
                 slug: "legacy-sequence-demo",
                 name: "Legacy Sequence Demo",
                 repair_legacy_snapshot: true,
                 verify_user_id: installer.id,
                 verify_workspace_id: workspace.id
               )

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)
      register_project_asset_cleanup(template.source_project)

      assert {:ok, imported_asset_manifest} =
               SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      for imported_asset <- imported_asset_manifest["assets"] do
        on_exit(fn -> Assets.storage_delete(imported_asset["key"]) end)
      end

      repair_audit = version.audit_report["legacy_snapshot_repair"]
      materialization_audit = version.audit_report["import_materialization"]
      assert repair_audit == repair_preview
      assert materialization_audit["status"] == "passed"
      assert materialization_audit["errors"] == []
      assert materialization_audit["snapshot_counts"] == materialization_audit["recovered_counts"]

      assert {:ok, installed_project} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{
                 name: "Recovered Legacy Sequence"
               })

      for installed_asset <- Assets.list_assets(installed_project.id) do
        on_exit(fn -> Assets.storage_delete(installed_asset.key) end)
      end

      [installed_flow] = Flows.list_flows(installed_project.id)
      installed_flow = Repo.preload(installed_flow, :nodes)

      assert [recovery_annotation] =
               Enum.filter(installed_flow.nodes, fn node ->
                 get_in(node.data, ["legacy_recovery", "original_id"]) == sequence.id
               end)

      assert recovery_annotation.type == "annotation"

      assert recovery_annotation.data["legacy_recovery"] == %{
               "original_id" => sequence.id,
               "original_type" => "sequence"
             }

      refute Enum.any?(installed_flow.nodes, &(&1.type == "sequence"))

      install = Repo.get_by!(ProjectTemplateInstall, project_id: installed_project.id)
      assert install.status == "completed"
      assert install.stage == "completed"
      assert is_nil(install.error_code)
      assert install.error_report == %{}
      assert {:ok, %{"status" => "passed"}} = Audit.run(installed_project.id)

      assert {:ok, republished_template} =
               ProjectTemplates.create_template_from_project(scope, installed_project, %{
                 name: "Republished Legacy Recovery"
               })

      assert republished_template.source_project_id == installed_project.id
      republished_version = Repo.get!(ProjectTemplateVersion, republished_template.current_version_id)
      register_template_artifact_cleanup(republished_version)
      assert republished_version.audit_report["status"] == "passed"
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

    test "portable previews ignore untrusted legacy repair metadata when repair is not requested" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      malformed_path = bundle_path()
      forged_path = bundle_path()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(malformed_path)
        File.rm(forged_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)

      malformed_manifest =
        Map.put(bundle.manifest, "legacy_snapshot_repair", %{
          "repaired_sequence_count" => 1,
          "localization" => nil,
          "warning" => "Malformed report"
        })

      assert {:ok, ^malformed_path} =
               PortableBundle.write(
                 malformed_path,
                 malformed_manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      forged_manifest =
        Map.put(bundle.manifest, "legacy_snapshot_repair", %{
          "repaired_sequence_count" => 42,
          "localization" => %{"removed_count" => 42},
          "warning" => "FORGED REPAIR REPORT"
        })

      assert {:ok, ^forged_path} =
               PortableBundle.write(
                 forged_path,
                 forged_manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      for path <- [malformed_path, forged_path] do
        assert {:ok, preview} = ProjectTemplates.preview_portable_template(path)
        refute Map.has_key?(preview, "legacy_snapshot_repair")
      end
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
      slug = "failed-materialization-cleanup-#{System.unique_integer([:positive])}"

      on_exit(fn ->
        File.rm(output_path)
        File.rm(incompatible_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path, slug: slug)

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
      assert imported_blob_files(slug) == []
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

    test "rejects a private import whose owner would not own the source project" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()
      different_owner = AccountsFixtures.user_fixture()

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)

      assert {:error, :private_template_owner_must_match_verify_user} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "private",
                 owner_id: different_owner.id,
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )
    end

    test "rejects a public import whose editable source could not be managed later" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      user = AccountsFixtures.user_fixture()
      workspace = WorkspacesFixtures.workspace_fixture(user)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)

      assert {:error, :public_template_source_requires_super_admin} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 verify_user_id: user.id,
                 verify_workspace_id: workspace.id
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

    test "update_existing repairs a legacy public template by materializing its editable source" do
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()
      scope = AccountsFixtures.user_scope_fixture(verify_user)
      existing = public_template_with_slug!("veilbreak-demo")

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Veilbreak Demo",
                 slug: "veilbreak-demo"
               )

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 update_existing: true,
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert template.id == existing.id
      assert %Project{} = template.source_project
      assert template.source_project_id == template.source_project.id
      assert ProjectTemplates.can_manage_template?(scope, template)
      register_project_asset_cleanup(template.source_project)

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      assert version.source_project_id == template.source_project_id
      register_template_artifact_cleanup(version)

      assert {:ok, %{"assets" => assets}} =
               SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)

      Enum.each(assets, fn %{"key" => key} -> on_exit(fn -> Assets.storage_delete(key) end) end)
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
    user = AccountsFixtures.set_super_admin(AccountsFixtures.user_fixture())
    workspace = WorkspacesFixtures.workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  defp asset_files(bundle) do
    Enum.map(bundle.manifest["asset_blobs"], fn blob ->
      {blob["path"], bundle.files[blob["path"]]}
    end)
  end

  defp imported_blob_files(slug) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)

    upload_dir
    |> Path.join("project_templates/imported_blobs/#{slug}/**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp homogeneous_legacy_sequence_snapshot(snapshot) do
    update_in(snapshot, ["flows", Access.all(), "snapshot", "nodes", Access.all()], fn node ->
      node = Map.delete(node, "parent_id")

      if node["type"] == "sequence" do
        node
        |> Map.delete("sequence_config")
        |> Map.delete("sequence_tracks")
        |> Map.delete("sequence_visual_layers")
      else
        node
      end
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

  defp register_project_asset_cleanup(project) do
    storage_keys =
      project.id
      |> Assets.list_assets()
      |> Enum.flat_map(fn asset ->
        [
          asset.key,
          BlobStore.blob_key(
            project.id,
            asset.blob_hash,
            BlobStore.ext_from_content_type(asset.content_type)
          )
        ]
      end)
      |> Enum.uniq()

    on_exit(fn -> Enum.each(storage_keys, &Assets.storage_delete/1) end)
  end
end
