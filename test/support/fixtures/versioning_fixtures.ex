defmodule Storyarn.VersioningFixtures do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot

  def pending_project_snapshot_fixture(project, attrs \\ %{}) do
    attrs = Map.new(attrs)
    version_number = Map.get_lazy(attrs, :version_number, fn -> next_version_number(project.id) end)
    object_prefix = Map.get(attrs, :object_prefix, ready_prefix(project.id))

    defaults = %{
      project_id: project.id,
      version_number: version_number,
      title: "Snapshot #{version_number}",
      object_prefix: object_prefix,
      project_size_bytes: 100,
      project_checksum: String.duplicate("a", 64),
      manifest_size_bytes: 50,
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: 150,
      object_count: 2,
      asset_count: 0,
      blob_count: 0,
      mode: "full",
      lifecycle_state: "pending",
      integrity_state: "unknown",
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: String.duplicate("c", 64),
      progress_total_bytes: 150,
      is_auto: false
    }

    %ProjectSnapshot{}
    |> ProjectSnapshot.pending_object_set_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def full_project_snapshot_fixture(project, attrs \\ %{}) do
    attrs = Map.new(attrs)
    version_number = Map.get_lazy(attrs, :version_number, fn -> next_version_number(project.id) end)
    object_prefix = Map.get(attrs, :object_prefix, ready_prefix(project.id))
    project_size = Map.get(attrs, :project_size_bytes, 100)
    manifest_size = Map.get(attrs, :manifest_size_bytes, 50)
    asset_blob_size = Map.get(attrs, :asset_blob_size_bytes, 25)
    asset_count = Map.get(attrs, :asset_count, if(asset_blob_size > 0, do: 1, else: 0))
    blob_count = Map.get(attrs, :blob_count, if(asset_blob_size > 0, do: 1, else: 0))

    now = Storyarn.Shared.TimeHelpers.now()
    inserted_at = Map.get(attrs, :inserted_at, now)
    attrs = Map.delete(attrs, :inserted_at)

    defaults = %{
      project_id: project.id,
      version_number: version_number,
      title: "Snapshot #{version_number}",
      project_storage_key: object_prefix <> "/project.json",
      project_size_bytes: project_size,
      project_checksum: String.duplicate("a", 64),
      entity_counts: %{},
      format_version: 1,
      object_prefix: object_prefix,
      manifest_storage_key: object_prefix <> "/manifest.json",
      manifest_size_bytes: manifest_size,
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: project_size + manifest_size + asset_blob_size,
      object_count: blob_count + 2,
      asset_count: asset_count,
      blob_count: blob_count,
      mode: "full",
      lifecycle_state: "ready",
      integrity_state: "verified",
      accounted_size_bytes: project_size + manifest_size + asset_blob_size,
      asset_blob_size_bytes: asset_blob_size,
      accounting_version: 1,
      progress_phase: "complete",
      progress_bytes: project_size + manifest_size + asset_blob_size,
      progress_total_bytes: project_size + manifest_size + asset_blob_size,
      verifying_started_at: now,
      ready_at: now,
      state_updated_at: now,
      is_auto: false
    }

    %ProjectSnapshot{
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: String.duplicate("c", 64),
      captured_at: inserted_at,
      build_attempt: 1,
      building_started_at: now,
      inserted_at: inserted_at
    }
    |> ProjectSnapshot.object_set_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp next_version_number(project_id) do
    (Repo.one(
       from(snapshot in ProjectSnapshot,
         where: snapshot.project_id == ^project_id,
         select: max(snapshot.version_number)
       )
     ) || 0) + 1
  end

  defp ready_prefix(project_id) do
    token =
      12
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "projects/#{project_id}/snapshots/object-sets/v1/ready/#{token}"
  end
end
