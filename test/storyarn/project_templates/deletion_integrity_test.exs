defmodule Storyarn.ProjectTemplates.DeletionIntegrityTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.AccountsFixtures
  alias Storyarn.Assets
  alias Storyarn.ProjectsFixtures
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.Artifact
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker

  describe "portable artifact lifecycle" do
    test "hard deletion enqueues and removes imported snapshot, manifest, and blobs" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)

      assert {:ok, deleted} = ProjectTemplates.delete_template(scope, artifact.template)
      assert deleted.id == artifact.template.id
      assert Repo.get(ProjectTemplate, artifact.template.id) == nil
      assert Repo.get(ProjectTemplateVersion, artifact.version.id) == nil
      assert Repo.get(ProjectTemplatePublication, artifact.publication.id) == nil

      storage_keys = [artifact.snapshot_key, artifact.manifest_key, artifact.blob_key]

      assert_enqueued(
        worker: DeleteProjectTemplateArtifactsWorker,
        args: %{"storage_keys" => storage_keys}
      )

      assert :ok =
               perform_job(DeleteProjectTemplateArtifactsWorker, %{
                 "storage_keys" => storage_keys
               })

      assert {:error, _reason} = SnapshotStorage.load_snapshot(artifact.snapshot_key)
      assert {:error, _reason} = SnapshotStorage.load_snapshot(artifact.manifest_key)
      assert {:error, _reason} = Assets.storage_download(artifact.blob_key)
    end

    test "an unavailable imported manifest prevents hard deletion and preserves every known artifact" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)

      assert :ok = Assets.storage_delete(artifact.manifest_key)

      assert {:error, {:portable_asset_manifest_unavailable, manifest_key, _reason}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == artifact.manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert Repo.get(ProjectTemplateVersion, artifact.version.id)
      assert Repo.get(ProjectTemplatePublication, artifact.publication.id)
      assert {:ok, _snapshot} = SnapshotStorage.load_snapshot(artifact.snapshot_key)
      assert {:ok, _blob} = Assets.storage_download(artifact.blob_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "a checksum mismatch prevents a tampered manifest from contributing GC targets" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)
      tampered_manifest = put_in(artifact.manifest, ["assets", Access.at(0), "filename"], "tampered.bin")

      assert {:ok, _size} = SnapshotStorage.store_raw(artifact.manifest_key, tampered_manifest)

      assert {:error, {:invalid_portable_artifact, manifest_key, :checksum_mismatch}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == artifact.manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert {:ok, _blob} = Assets.storage_download(artifact.blob_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "even a checksummed manifest cannot target another import namespace" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)
      external_blob = "external-portable-template-blob"
      external_hash = sha256(external_blob)
      external_suffix = SnapshotStorage.unique_key_suffix()

      external_key =
        "project_templates/imported_blobs/another-template/#{external_suffix}/#{external_hash}/external.bin"

      assert {:ok, _url} =
               Assets.storage_upload(external_key, external_blob, "application/octet-stream")

      register_storage_cleanup([external_key])

      external_manifest =
        artifact.manifest
        |> put_in(["assets", Access.at(0), "blob_hash"], external_hash)
        |> put_in(["assets", Access.at(0), "key"], external_key)

      assert {:ok, _size} = SnapshotStorage.store_raw(artifact.manifest_key, external_manifest)

      checksum =
        Artifact.checksum(%{
          "snapshot" => artifact.snapshot,
          "asset_manifest" => external_manifest
        })

      artifact.version
      |> change(checksum: checksum)
      |> Repo.update!()

      artifact.publication
      |> change(checksum: checksum)
      |> Repo.update!()

      assert {:error, {:template_asset_manifest_unreadable, manifest_key, :invalid_asset_manifest}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == artifact.manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert {:ok, ^external_blob} = Assets.storage_download(external_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "even a checksummed manifest cannot target a nested filename inside its blob namespace" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)
      nested_key = Path.dirname(artifact.blob_key) <> "/nested/asset.bin"

      assert {:ok, _url} =
               Assets.storage_upload(nested_key, "nested-portable-blob", "application/octet-stream")

      register_storage_cleanup([nested_key])

      nested_manifest = put_in(artifact.manifest, ["assets", Access.at(0), "key"], nested_key)
      assert {:ok, _size} = SnapshotStorage.store_raw(artifact.manifest_key, nested_manifest)

      checksum =
        Artifact.checksum(%{
          "snapshot" => artifact.snapshot,
          "asset_manifest" => nested_manifest
        })

      artifact.version
      |> change(checksum: checksum)
      |> Repo.update!()

      artifact.publication
      |> change(checksum: checksum)
      |> Repo.update!()

      assert {:error, {:template_asset_manifest_unreadable, manifest_key, :invalid_asset_manifest}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == artifact.manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert {:ok, "nested-portable-blob"} = Assets.storage_download(nested_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "portable artifacts reject a sibling snapshot key in the same import directory" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)
      sibling_snapshot_key = String.replace_suffix(artifact.snapshot_key, "snapshot.json.gz", "snapshot-copy.json.gz")

      assert {:ok, _size} = SnapshotStorage.store_raw(sibling_snapshot_key, artifact.snapshot)
      register_storage_cleanup([sibling_snapshot_key])

      artifact.version
      |> change(snapshot_storage_key: sibling_snapshot_key)
      |> Repo.update!()

      artifact.publication
      |> change(snapshot_storage_key: sibling_snapshot_key)
      |> Repo.update!()

      assert {:error, {:invalid_portable_artifact, manifest_key, :invalid_snapshot_storage_key}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == artifact.manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert {:ok, _snapshot} = SnapshotStorage.load_snapshot(sibling_snapshot_key)
      assert {:ok, _blob} = Assets.storage_download(artifact.blob_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "portable artifacts reject a noncanonical manifest filename" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)

      sibling_manifest_key =
        String.replace_suffix(
          artifact.manifest_key,
          "asset-manifest.json.gz",
          "asset-manifest-copy.json.gz"
        )

      assert {:ok, _size} = SnapshotStorage.store_raw(sibling_manifest_key, artifact.manifest)
      register_storage_cleanup([sibling_manifest_key])

      artifact.version
      |> change(asset_manifest_storage_key: sibling_manifest_key)
      |> Repo.update!()

      artifact.publication
      |> change(asset_manifest_storage_key: sibling_manifest_key)
      |> Repo.update!()

      assert {:error, {:invalid_portable_artifact, manifest_key, :invalid_manifest_storage_key}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert manifest_key == sibling_manifest_key
      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert {:ok, _manifest} = SnapshotStorage.load_snapshot(sibling_manifest_key)
      assert {:ok, _blob} = Assets.storage_download(artifact.blob_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "an unavailable canonical internal manifest does not block deletion" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = internal_template_with_missing_manifest_fixture(user, project)
      storage_keys = [artifact.snapshot_key, artifact.manifest_key]

      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, artifact.template)
      assert Repo.get(ProjectTemplate, artifact.template.id) == nil

      assert_enqueued(
        worker: DeleteProjectTemplateArtifactsWorker,
        args: %{"storage_keys" => storage_keys}
      )
    end

    test "an artifact row that targets another project's asset fails closed before deletion" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      source_project = ProjectsFixtures.project_fixture(user)
      external_project = ProjectsFixtures.project_fixture(user)
      suffix = SnapshotStorage.unique_key_suffix()
      external_key = "projects/#{external_project.id}/assets/#{Ecto.UUID.generate()}/foreign.bin"

      assert {:ok, _url} =
               Assets.storage_upload(external_key, "external project asset", "application/octet-stream")

      register_storage_cleanup([external_key])

      invalid_manifest_key =
        "project_template_publications/1/asset-manifest-#{suffix}.json.gz"

      artifact =
        template_version_fixture(
          user,
          source_project,
          "external-asset-target-#{suffix}",
          external_key,
          invalid_manifest_key,
          String.duplicate("0", 64)
        )

      assert {:error, {:invalid_artifact_storage_key, ^external_key}} =
               ProjectTemplates.delete_template(scope, artifact.template)

      assert Repo.get(ProjectTemplate, artifact.template.id)
      assert Repo.get(ProjectTemplateVersion, artifact.version.id)
      assert {:ok, "external project asset"} = Assets.storage_download(external_key)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)
    end

    test "shared internal artifacts remain reachable from another template" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      owner = internal_template_fixture(user, project)
      suffix = SnapshotStorage.unique_key_suffix()

      shared =
        template_version_fixture(
          user,
          project,
          "shared-internal-#{suffix}",
          owner.snapshot_key,
          owner.manifest_key,
          owner.checksum
        )

      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, shared.template)
      assert Repo.get(ProjectTemplate, shared.template.id) == nil
      assert Repo.get(ProjectTemplate, owner.template.id)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)

      assert {:ok, owner.snapshot} == SnapshotStorage.load_snapshot(owner.snapshot_key)
      assert {:ok, owner.manifest} == SnapshotStorage.load_snapshot(owner.manifest_key)
    end

    test "shared portable artifacts preserve the complete snapshot, manifest, and blob group" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      owner = imported_template_fixture(user, project)
      suffix = SnapshotStorage.unique_key_suffix()

      shared =
        template_version_fixture(
          user,
          project,
          "shared-portable-#{suffix}",
          owner.snapshot_key,
          owner.manifest_key,
          owner.version.checksum
        )

      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, shared.template)
      assert Repo.get(ProjectTemplate, shared.template.id) == nil
      assert Repo.get(ProjectTemplate, owner.template.id)
      refute_enqueued(worker: DeleteProjectTemplateArtifactsWorker)

      assert {:ok, owner.snapshot} == SnapshotStorage.load_snapshot(owner.snapshot_key)
      assert {:ok, owner.manifest} == SnapshotStorage.load_snapshot(owner.manifest_key)
      assert {:ok, "portable-template-blob"} = Assets.storage_download(owner.blob_key)
    end

    test "GC preserves internal artifacts referenced after deletion was enqueued" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = internal_template_fixture(user, project)
      storage_keys = [artifact.snapshot_key, artifact.manifest_key]

      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, artifact.template)

      suffix = SnapshotStorage.unique_key_suffix()

      late_reference =
        template_version_fixture(
          user,
          project,
          "late-internal-reference-#{suffix}",
          artifact.snapshot_key,
          artifact.manifest_key,
          artifact.checksum
        )

      assert Repo.get(ProjectTemplateVersion, late_reference.version.id)

      assert :ok =
               perform_job(DeleteProjectTemplateArtifactsWorker, %{
                 "storage_keys" => storage_keys
               })

      assert {:ok, artifact.snapshot} == SnapshotStorage.load_snapshot(artifact.snapshot_key)
      assert {:ok, artifact.manifest} == SnapshotStorage.load_snapshot(artifact.manifest_key)
    end

    test "GC preserves a complete portable group referenced after deletion was enqueued" do
      user = AccountsFixtures.user_fixture()
      scope = AccountsFixtures.user_scope_fixture(user)
      project = ProjectsFixtures.project_fixture(user)
      artifact = imported_template_fixture(user, project)
      storage_keys = [artifact.snapshot_key, artifact.manifest_key, artifact.blob_key]

      assert {:ok, _deleted} = ProjectTemplates.delete_template(scope, artifact.template)

      suffix = SnapshotStorage.unique_key_suffix()

      late_reference =
        template_version_fixture(
          user,
          project,
          "late-portable-reference-#{suffix}",
          artifact.snapshot_key,
          artifact.manifest_key,
          artifact.version.checksum
        )

      assert Repo.get(ProjectTemplateVersion, late_reference.version.id)

      assert :ok =
               perform_job(DeleteProjectTemplateArtifactsWorker, %{
                 "storage_keys" => storage_keys
               })

      assert {:ok, artifact.snapshot} == SnapshotStorage.load_snapshot(artifact.snapshot_key)
      assert {:ok, artifact.manifest} == SnapshotStorage.load_snapshot(artifact.manifest_key)
      assert {:ok, "portable-template-blob"} = Assets.storage_download(artifact.blob_key)
    end

    test "the artifact GC boundary rejects non-template storage keys" do
      external_key = "projects/1/assets/#{Ecto.UUID.generate()}/foreign.bin"

      assert {:ok, _url} =
               Assets.storage_upload(external_key, "protected external asset", "application/octet-stream")

      register_storage_cleanup([external_key])

      assert {:error, {:invalid_template_storage_keys, [^external_key]}} =
               ProjectTemplates.perform_template_artifact_gc([external_key])

      assert {:error, {:invalid_template_storage_keys, [^external_key]}} =
               perform_job(DeleteProjectTemplateArtifactsWorker, %{
                 "storage_keys" => [external_key]
               })

      assert {:ok, "protected external asset"} = Assets.storage_download(external_key)
    end
  end

  defp imported_template_fixture(user, project) do
    suffix = SnapshotStorage.unique_key_suffix()
    slug = "portable-delete-#{suffix}"
    blob = "portable-template-blob"
    blob_hash = sha256(blob)
    blob_key = "project_templates/imported_blobs/#{slug}/#{suffix}/#{blob_hash}/blob"
    snapshot_key = "project_templates/imports/#{slug}/#{suffix}/snapshot.json.gz"
    manifest_key = "project_templates/imports/#{slug}/#{suffix}/asset-manifest.json.gz"
    snapshot = %{"format_version" => 1}

    assert {:ok, _url} = Assets.storage_upload(blob_key, blob, "application/octet-stream")

    manifest = %{
      "format_version" => 1,
      "assets" => [
        %{
          "blob_hash" => blob_hash,
          "content_type" => "application/octet-stream",
          "filename" => "asset.bin",
          "key" => blob_key,
          "size" => byte_size(blob)
        }
      ],
      "asset_count" => 1
    }

    checksum = Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => manifest})

    assert {:ok, _size} = SnapshotStorage.store_raw(snapshot_key, snapshot)
    assert {:ok, _size} = SnapshotStorage.store_raw(manifest_key, manifest)

    register_storage_cleanup([snapshot_key, manifest_key, blob_key])

    %{template: template, version: version} =
      template_version_fixture(user, project, slug, snapshot_key, manifest_key, checksum)

    publication =
      published_publication_fixture(
        user,
        project,
        template,
        version,
        snapshot_key,
        manifest_key,
        checksum
      )

    %{
      template: template,
      version: version,
      publication: publication,
      snapshot_key: snapshot_key,
      manifest_key: manifest_key,
      blob_key: blob_key,
      snapshot: snapshot,
      manifest: manifest
    }
  end

  defp internal_template_with_missing_manifest_fixture(user, project) do
    internal_template_fixture(user, project, store_manifest?: false)
  end

  defp internal_template_fixture(user, project, opts \\ []) do
    suffix = SnapshotStorage.unique_key_suffix()
    slug = "internal-delete-#{suffix}"
    template = template_fixture(user, project, slug)

    publication =
      %ProjectTemplatePublication{
        owner_id: user.id,
        requested_by_id: user.id,
        source_project_id: project.id,
        project_template_id: template.id
      }
      |> ProjectTemplatePublication.create_changeset(%{
        "mode" => "update",
        "status" => "failed",
        "name" => "Deletion integrity"
      })
      |> Repo.insert!()

    snapshot_key =
      "project_template_publications/#{publication.id}/snapshot-#{SnapshotStorage.unique_key_suffix()}.json.gz"

    manifest_key =
      "project_template_publications/#{publication.id}/asset-manifest-#{SnapshotStorage.unique_key_suffix()}.json.gz"

    snapshot = %{"format_version" => 1}
    manifest = %{"format_version" => 1, "assets" => [], "asset_count" => 0}
    checksum = Artifact.checksum(%{"snapshot" => snapshot, "asset_manifest" => manifest})

    assert {:ok, _size} = SnapshotStorage.store_raw(snapshot_key, snapshot)

    if Keyword.get(opts, :store_manifest?, true) do
      assert {:ok, _size} = SnapshotStorage.store_raw(manifest_key, manifest)
    end

    register_storage_cleanup([snapshot_key, manifest_key])

    %{template: template, version: version} =
      version_fixture(
        user,
        project,
        template,
        snapshot_key,
        manifest_key,
        checksum
      )

    publication =
      publication
      |> ProjectTemplatePublication.published_changeset(%{
        "status" => "published",
        "project_template_id" => template.id,
        "project_template_version_id" => version.id,
        "snapshot_storage_key" => snapshot_key,
        "asset_manifest_storage_key" => manifest_key,
        "checksum" => checksum,
        "entity_counts" => %{},
        "preview" => %{},
        "audit_report" => %{},
        "completed_at" => DateTime.utc_now(:second)
      })
      |> Repo.update!()

    %{
      template: template,
      version: version,
      publication: publication,
      snapshot_key: snapshot_key,
      manifest_key: manifest_key,
      snapshot: snapshot,
      manifest: manifest,
      checksum: checksum
    }
  end

  defp template_version_fixture(user, project, slug, snapshot_key, manifest_key, checksum) do
    template = template_fixture(user, project, slug)
    version_fixture(user, project, template, snapshot_key, manifest_key, checksum)
  end

  defp version_fixture(user, project, template, snapshot_key, manifest_key, checksum) do
    version =
      %ProjectTemplateVersion{
        project_template_id: template.id,
        source_project_id: project.id,
        published_by_id: user.id
      }
      |> ProjectTemplateVersion.create_changeset(%{
        "version_number" => 1,
        "snapshot_storage_key" => snapshot_key,
        "asset_manifest_storage_key" => manifest_key,
        "checksum" => checksum,
        "entity_counts" => %{},
        "preview" => %{},
        "audit_report" => %{},
        "published_at" => DateTime.utc_now(:second)
      })
      |> Repo.insert!()

    template =
      template
      |> ProjectTemplate.current_version_changeset(version.id)
      |> Repo.update!()

    %{template: template, version: version}
  end

  defp template_fixture(user, project, slug) do
    %ProjectTemplate{owner_id: user.id, source_project_id: project.id}
    |> ProjectTemplate.create_changeset(%{
      "name" => "Deletion integrity",
      "slug" => slug,
      "visibility" => "private",
      "status" => "archived"
    })
    |> Repo.insert!()
  end

  defp published_publication_fixture(user, project, template, version, snapshot_key, manifest_key, checksum) do
    %ProjectTemplatePublication{
      owner_id: user.id,
      requested_by_id: user.id,
      source_project_id: project.id,
      mode: "new",
      name: "Deletion integrity"
    }
    |> ProjectTemplatePublication.published_changeset(%{
      "status" => "published",
      "project_template_id" => template.id,
      "project_template_version_id" => version.id,
      "snapshot_storage_key" => snapshot_key,
      "asset_manifest_storage_key" => manifest_key,
      "checksum" => checksum,
      "entity_counts" => %{},
      "preview" => %{},
      "audit_report" => %{},
      "completed_at" => DateTime.utc_now(:second)
    })
    |> Repo.insert!()
  end

  defp register_storage_cleanup(storage_keys) do
    on_exit(fn ->
      Enum.each(storage_keys, &Assets.storage_delete/1)
    end)
  end

  defp sha256(data) do
    data
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
