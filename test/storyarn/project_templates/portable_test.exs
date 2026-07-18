defmodule Storyarn.ProjectTemplates.PortableTest do
  use Storyarn.DataCase, async: false

  alias Mix.Tasks.Storyarn.Templates.Export, as: ExportTask
  alias Mix.Tasks.Storyarn.Templates.Import, as: ImportTask
  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.FlowsFixtures
  alias Storyarn.Localization
  alias Storyarn.LocalizationFixtures
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

      # The imported template must be independent from storage in the source
      # deployment. Materialization and later installation can only use the
      # checksummed blob uploaded by PortableImport.
      delete_storage_blob(BlobStore.blob_key(project.id, source_asset.blob_hash, "png"))

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

    test "imports and installs global voice-over from the verified portable blob catalog" do
      %{project: project, voice_asset: voice_asset} = portable_voice_source_project()
      output_path = bundle_path()
      installer = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(installer)
      workspace = WorkspacesFixtures.workspace_fixture(installer)

      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Voiced Demo",
                 slug: "voiced-demo"
               )

      delete_storage_blob(BlobStore.blob_key(project.id, voice_asset.blob_hash, "mp3"))

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 slug: "voiced-demo",
                 verify_user_id: installer.id,
                 verify_workspace_id: workspace.id
               )

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)

      assert {:ok, cloned_project} =
               ProjectTemplates.instantiate_template(scope, version, workspace, %{
                 name: "Installed Voiced Demo"
               })

      cloned_text =
        cloned_project.id
        |> Localization.list_texts_for_export(["es"])
        |> Enum.find(& &1.vo_asset_id)

      cloned_voice_asset = Repo.get!(Asset, cloned_text.vo_asset_id)

      assert cloned_text.vo_status == "recorded"
      assert cloned_voice_asset.project_id == cloned_project.id
      assert cloned_voice_asset.blob_hash == voice_asset.blob_hash
      assert {:ok, "portable voice-over"} = Assets.storage_download(cloned_voice_asset.key)
      on_exit(fn -> Assets.storage_delete(cloned_voice_asset.key) end)
    end

    test "an incomplete portable source catalog is rejected before database or storage mutation" do
      original_storage_config = Application.fetch_env!(:storyarn, :storage)

      isolated_upload_dir =
        Path.join(
          System.tmp_dir!(),
          "storyarn-portable-rollback-#{System.unique_integer([:positive])}"
        )

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :upload_dir, isolated_upload_dir)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, :storage, original_storage_config)
        File.rm_rf!(isolated_upload_dir)
      end)

      %{project: project, voice_asset: voice_asset} = portable_voice_source_project()
      output_path = bundle_path()
      incomplete_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(incomplete_path)
      end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Incomplete Voice Demo",
                 slug: "incomplete-voice-demo"
               )

      assert {:ok, bundle} = PortableBundle.read(output_path)

      retained_blobs =
        Enum.reject(bundle.manifest["asset_blobs"], &(&1["sha256"] == voice_asset.blob_hash))

      retained_asset_manifest =
        bundle.asset_manifest
        |> Map.update!("assets", fn assets ->
          Enum.reject(assets, &(&1["blob_hash"] == voice_asset.blob_hash))
        end)
        |> Map.put("asset_count", length(retained_blobs))

      incomplete_manifest =
        bundle.manifest
        |> Map.put("asset_blobs", retained_blobs)
        |> Map.put("asset_count", length(retained_blobs))
        |> Map.put(
          "checksum",
          PortableBundle.checksum(bundle.snapshot, retained_asset_manifest, retained_blobs)
        )

      retained_files =
        Enum.map(retained_blobs, fn blob ->
          {blob["path"], bundle.files[blob["path"]]}
        end)

      assert {:ok, _path} =
               PortableBundle.write(
                 incomplete_path,
                 incomplete_manifest,
                 bundle.snapshot,
                 retained_asset_manifest,
                 retained_files
               )

      projects_before = Repo.aggregate(Project, :count)
      assets_before = Repo.aggregate(Asset, :count)
      storage_before = storage_files()

      assert {:error, :inconsistent_bundle_asset_catalog} =
               ProjectTemplates.import_portable_template(incomplete_path,
                 visibility: "public",
                 slug: "incomplete-voice-demo",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert Repo.aggregate(Project, :count) == projects_before
      assert Repo.aggregate(Asset, :count) == assets_before
      assert storage_files() == storage_before
    end

    test "deduplicates uploads by hash while preserving distinct asset descriptors" do
      isolate_storage!()
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(user, %{name: "Shared Blob Source"})
      sheet = SheetsFixtures.sheet_fixture(project, %{name: "Twins"})
      first_asset = uploaded_image_asset(project, user, "first.png", "shared portable bytes")
      second_asset = uploaded_image_asset(project, user, "second.png", "shared portable bytes")
      assert first_asset.blob_hash == second_asset.blob_hash
      {:ok, _first_avatar} = Sheets.add_avatar(sheet, first_asset.id, %{name: "First"})
      {:ok, _second_avatar} = Sheets.add_avatar(sheet, second_asset.id, %{name: "Second"})

      output_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()
      on_exit(fn -> File.rm(output_path) end)

      assert {:ok, _export} =
               ProjectTemplates.export_portable_template(project.id, output_path,
                 name: "Shared Blob Demo",
                 slug: "shared-blob-demo"
               )

      assert {:ok, bundle} = PortableBundle.read(output_path)
      assert [first_blob, second_blob] = bundle.manifest["asset_blobs"]
      assert first_blob["sha256"] == second_blob["sha256"]
      refute first_blob["asset_id"] == second_blob["asset_id"]
      refute first_blob["path"] == second_blob["path"]

      assert {:ok, template} =
               ProjectTemplates.import_portable_template(output_path,
                 visibility: "public",
                 slug: "shared-blob-demo",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      register_template_artifact_cleanup(version)
      assert {:ok, imported_manifest} = SnapshotStorage.load_snapshot(version.asset_manifest_storage_key)
      assert imported_manifest["asset_count"] == 2

      imported_keys =
        imported_manifest["assets"]
        |> Enum.map(& &1["key"])
        |> Enum.uniq()

      assert [imported_key] = imported_keys
      assert imported_key =~ "project_templates/imported_blobs/shared-blob-demo/"
      assert String.ends_with?(imported_key, "/#{first_asset.blob_hash}/blob")
      on_exit(fn -> Assets.storage_delete(imported_key) end)

      imported_storage_objects =
        Enum.filter(storage_files(), &String.starts_with?(&1, "project_templates/imported_blobs/shared-blob-demo/"))

      assert [^imported_key] = imported_storage_objects
    end

    test "rejects a checksummed asset manifest without its format before mutation" do
      isolate_storage!()
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      malformed_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(malformed_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)
      malformed_asset_manifest = Map.delete(bundle.asset_manifest, "format_version")

      manifest =
        Map.put(
          bundle.manifest,
          "checksum",
          PortableBundle.checksum(
            bundle.snapshot,
            malformed_asset_manifest,
            bundle.manifest["asset_blobs"]
          )
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 malformed_path,
                 manifest,
                 bundle.snapshot,
                 malformed_asset_manifest,
                 asset_files(bundle)
               )

      storage_before = storage_files()
      templates_before = Repo.aggregate(ProjectTemplate, :count)
      versions_before = Repo.aggregate(ProjectTemplateVersion, :count)

      assert {:error, :invalid_bundle_asset_manifest} =
               ProjectTemplates.import_portable_template(malformed_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert Repo.aggregate(ProjectTemplate, :count) == templates_before
      assert Repo.aggregate(ProjectTemplateVersion, :count) == versions_before
      assert storage_files() == storage_before
    end

    test "rejects nested malformed snapshot collections without raising or mutating" do
      isolate_storage!()
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      malformed_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(malformed_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)

      malformed_snapshot =
        update_in(bundle.snapshot, ["sheets"], fn [sheet | rest] ->
          [put_in(sheet, ["snapshot", "blocks"], %{"not" => "a list"}) | rest]
        end)

      manifest =
        Map.put(
          bundle.manifest,
          "checksum",
          PortableBundle.checksum(
            malformed_snapshot,
            bundle.asset_manifest,
            bundle.manifest["asset_blobs"]
          )
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 malformed_path,
                 manifest,
                 malformed_snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle)
               )

      storage_before = storage_files()
      templates_before = Repo.aggregate(ProjectTemplate, :count)

      assert {:error, :invalid_bundle_snapshot} =
               ProjectTemplates.import_portable_template(malformed_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert Repo.aggregate(ProjectTemplate, :count) == templates_before
      assert storage_files() == storage_before
    end

    test "rejects a checksummed extra blob before uploading any artifact" do
      isolate_storage!()
      %{project: project, asset: asset} = portable_source_project()
      output_path = bundle_path()
      extra_blob_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(extra_blob_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)
      extra_data = "unreferenced portable blob"
      extra_hash = BlobStore.compute_hash(extra_data)
      extra_asset_id = asset.id + 1_000_000
      extra_path = "assets/#{extra_hash}/#{extra_asset_id}-extra.png"

      extra_blob = %{
        "asset_id" => extra_asset_id,
        "path" => extra_path,
        "sha256" => extra_hash,
        "filename" => "extra.png",
        "content_type" => "image/png",
        "size" => byte_size(extra_data)
      }

      asset_blobs = bundle.manifest["asset_blobs"] ++ [extra_blob]

      manifest =
        bundle.manifest
        |> Map.put("asset_blobs", asset_blobs)
        |> Map.put("asset_count", length(asset_blobs))
        |> Map.put(
          "checksum",
          PortableBundle.checksum(bundle.snapshot, bundle.asset_manifest, asset_blobs)
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 extra_blob_path,
                 manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 asset_files(bundle) ++ [{extra_path, extra_data}]
               )

      storage_before = storage_files()
      templates_before = Repo.aggregate(ProjectTemplate, :count)

      assert {:error, :inconsistent_bundle_asset_catalog} =
               ProjectTemplates.import_portable_template(extra_blob_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert Repo.aggregate(ProjectTemplate, :count) == templates_before
      assert storage_files() == storage_before
    end

    test "rejects malicious portable SVG bytes before storage mutation" do
      isolate_storage!()
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      svg_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(svg_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)
      [original_blob] = bundle.manifest["asset_blobs"]
      malicious_svg = ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>|
      svg_hash = BlobStore.compute_hash(malicious_svg)
      svg_asset_path = "assets/#{svg_hash}/#{original_blob["asset_id"]}-malicious.svg"

      svg_blob =
        original_blob
        |> Map.put("sha256", svg_hash)
        |> Map.put("size", byte_size(malicious_svg))
        |> Map.put("content_type", "image/svg+xml")
        |> Map.put("filename", "malicious.svg")
        |> Map.put("path", svg_asset_path)

      svg_snapshot =
        rewrite_snapshot_asset_payload(
          bundle.snapshot,
          original_blob["sha256"],
          svg_hash,
          %{
            "filename" => "malicious.svg",
            "content_type" => "image/svg+xml",
            "size" => byte_size(malicious_svg),
            "sanitized_svg" => true
          }
        )

      svg_asset_manifest =
        update_in(bundle.asset_manifest, ["assets"], fn assets ->
          Enum.map(assets, fn asset ->
            asset
            |> Map.put("blob_hash", svg_hash)
            |> Map.put("filename", "malicious.svg")
            |> Map.put("content_type", "image/svg+xml")
            |> Map.put("size", byte_size(malicious_svg))
          end)
        end)

      manifest =
        bundle.manifest
        |> Map.put("asset_blobs", [svg_blob])
        |> Map.put(
          "checksum",
          PortableBundle.checksum(svg_snapshot, svg_asset_manifest, [svg_blob])
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 svg_path,
                 manifest,
                 svg_snapshot,
                 svg_asset_manifest,
                 [{svg_asset_path, malicious_svg}]
               )

      storage_before = storage_files()
      templates_before = Repo.aggregate(ProjectTemplate, :count)

      assert {:error, {:unsupported_portable_asset_content_type, _source, "image/svg+xml"}} =
               ProjectTemplates.import_portable_template(svg_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert Repo.aggregate(ProjectTemplate, :count) == templates_before
      assert storage_files() == storage_before
    end

    test "rejects unsafe checksummed descriptor filenames before upload" do
      isolate_storage!()
      %{project: project} = portable_source_project()
      output_path = bundle_path()
      unsafe_path = bundle_path()
      %{user: verify_user, workspace: verify_workspace} = verification_scope()

      on_exit(fn ->
        File.rm(output_path)
        File.rm(unsafe_path)
      end)

      assert {:ok, _export} = ProjectTemplates.export_portable_template(project.id, output_path)
      assert {:ok, bundle} = PortableBundle.read(output_path)
      [blob] = bundle.manifest["asset_blobs"]
      unsafe_blob = Map.put(blob, "filename", "..")

      manifest =
        bundle.manifest
        |> Map.put("asset_blobs", [unsafe_blob])
        |> Map.put(
          "checksum",
          PortableBundle.checksum(bundle.snapshot, bundle.asset_manifest, [unsafe_blob])
        )

      assert {:ok, _path} =
               PortableBundle.write(
                 unsafe_path,
                 manifest,
                 bundle.snapshot,
                 bundle.asset_manifest,
                 [{blob["path"], bundle.files[blob["path"]]}]
               )

      storage_before = storage_files()

      assert {:error, :invalid_bundle_asset_filename} =
               ProjectTemplates.import_portable_template(unsafe_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert storage_files() == storage_before
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
      isolate_storage!()
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

      storage_before = storage_files()
      templates_before = Repo.aggregate(ProjectTemplate, :count)
      versions_before = Repo.aggregate(ProjectTemplateVersion, :count)

      assert {:error, {:template_materialization_failed, report}} =
               ProjectTemplates.import_portable_template(incompatible_path,
                 visibility: "public",
                 verify_user_id: verify_user.id,
                 verify_workspace_id: verify_workspace.id
               )

      assert report["status"] == "failed"
      assert Repo.aggregate(ProjectTemplate, :count) == templates_before
      assert Repo.aggregate(ProjectTemplateVersion, :count) == versions_before
      assert storage_files() == storage_before
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

  defp portable_voice_source_project do
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(user, %{name: "Voiced Portable Source"})
    sheet = SheetsFixtures.sheet_fixture(project, %{name: "Narrator"})
    avatar_asset = uploaded_image_asset(project, user, "narrator.png", "portable narrator")
    {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Default"})

    LocalizationFixtures.source_language_fixture(project, %{locale_code: "en", name: "English"})
    LocalizationFixtures.language_fixture(project, %{locale_code: "es", name: "Spanish"})

    flow = FlowsFixtures.flow_fixture(project, %{name: "Voiced Flow"})
    node = FlowsFixtures.node_fixture(flow, %{type: "dialogue", data: %{"text" => "Listen"}})
    [text] = Localization.get_texts_for_source("flow_node", node.id)
    voice_asset = uploaded_audio_asset(project, user, "line.mp3", "portable voice-over")

    assert {:ok, _text} =
             Localization.update_text(text, %{
               translated_text: "Escucha",
               vo_asset_id: voice_asset.id,
               vo_status: "recorded"
             })

    %{project: project, user: user, voice_asset: voice_asset, avatar_asset: avatar_asset}
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
      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, "png"))
    end)

    asset
  end

  defp uploaded_audio_asset(project, user, filename, content) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "audio/mpeg", metadata: %{}, skip_variants: true},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, "mp3"))
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

  defp isolate_storage! do
    original_storage_config = Application.fetch_env!(:storyarn, :storage)

    isolated_upload_dir =
      Path.join(
        System.tmp_dir!(),
        "storyarn-portable-#{System.unique_integer([:positive])}"
      )

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage_config, :upload_dir, isolated_upload_dir)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage_config)
      File.rm_rf!(isolated_upload_dir)
    end)

    isolated_upload_dir
  end

  defp rewrite_snapshot_asset_payload(value, old_hash, new_hash, metadata_attrs) when is_map(value) do
    value =
      case {value["asset_blob_hashes"], value["asset_metadata"]} do
        {hashes, metadata} when is_map(hashes) and is_map(metadata) ->
          matching_ids =
            hashes
            |> Enum.filter(fn {_id, hash} -> hash == old_hash end)
            |> Enum.map(fn {id, _hash} -> to_string(id) end)

          rewritten_hashes =
            Map.new(hashes, fn {id, hash} ->
              {id, if(hash == old_hash, do: new_hash, else: hash)}
            end)

          rewritten_metadata =
            Map.new(metadata, fn {id, asset_metadata} ->
              rewrite_snapshot_asset_metadata(
                id,
                asset_metadata,
                matching_ids,
                metadata_attrs
              )
            end)

          value
          |> Map.put("asset_blob_hashes", rewritten_hashes)
          |> Map.put("asset_metadata", rewritten_metadata)

        _no_asset_catalog ->
          value
      end

    Map.new(value, fn {key, nested} ->
      {key, rewrite_snapshot_asset_payload(nested, old_hash, new_hash, metadata_attrs)}
    end)
  end

  defp rewrite_snapshot_asset_payload(value, old_hash, new_hash, metadata_attrs) when is_list(value) do
    Enum.map(
      value,
      &rewrite_snapshot_asset_payload(&1, old_hash, new_hash, metadata_attrs)
    )
  end

  defp rewrite_snapshot_asset_payload(value, _old_hash, _new_hash, _metadata_attrs), do: value

  defp rewrite_snapshot_asset_metadata(id, asset_metadata, matching_ids, metadata_attrs) do
    if to_string(id) in matching_ids and is_map(asset_metadata) do
      {id, Map.merge(asset_metadata, metadata_attrs)}
    else
      {id, asset_metadata}
    end
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
