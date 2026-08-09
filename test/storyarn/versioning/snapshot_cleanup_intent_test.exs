defmodule Storyarn.Versioning.SnapshotCleanupIntentTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotCleanupIntent

  describe "create_changeset/2" do
    test "accepts only objects beneath both exact owned prefixes" do
      attrs = valid_attrs()

      assert SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, attrs).valid?

      relative_paths = ["manifest.json", "project.json", "blobs/#{String.duplicate("a", 64)}.bin"]
      ready_keys = Enum.map(relative_paths, &"#{attrs.ready_prefix}/#{&1}")
      escaped_keys = ready_keys ++ relative_paths

      invalid_attrs =
        attrs
        |> Map.put(:storage_keys, escaped_keys)
        |> Map.put(:object_count, length(escaped_keys))
        |> Map.put(:inventory_digest, inventory_digest(escaped_keys))

      refute SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, invalid_attrs).valid?
    end

    test "rejects unsafe or ambiguous prefix pairs" do
      attrs = valid_attrs()

      repeated_slash =
        attrs
        |> Map.put(:ready_prefix, attrs.ready_prefix <> "/")
        |> rebuild_keys_and_digest()

      same_prefix =
        attrs
        |> Map.put(:staging_prefix, attrs.ready_prefix)
        |> rebuild_keys_and_digest()

      refute SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, repeated_slash).valid?
      refute SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, same_prefix).valid?
    end

    test "requires a lowercase provider namespace fingerprint" do
      attrs = valid_attrs()

      refute attrs
             |> Map.delete(:provider_namespace_fingerprint)
             |> then(&SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, &1))
             |> Map.fetch!(:valid?)

      refute attrs
             |> Map.put(:provider_namespace_fingerprint, String.duplicate("F", 64))
             |> then(&SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, &1))
             |> Map.fetch!(:valid?)
    end
  end

  describe "validate_persisted_inventory/1" do
    test "fails closed for corrupted original or remaining inventories" do
      intent = persisted_intent(valid_attrs())
      assert :ok = SnapshotCleanupIntent.validate_persisted_inventory(intent)

      assert {:error, :invalid_snapshot_cleanup_inventory} =
               intent
               |> Map.put(:remaining_storage_keys, ["manifest.json"])
               |> SnapshotCleanupIntent.validate_persisted_inventory()

      assert {:error, :invalid_snapshot_cleanup_inventory} =
               intent
               |> Map.put(:remaining_storage_keys, [])
               |> SnapshotCleanupIntent.validate_persisted_inventory()

      assert {:error, :invalid_snapshot_cleanup_inventory} =
               intent
               |> Map.put(:provider_namespace_fingerprint, String.duplicate("F", 64))
               |> SnapshotCleanupIntent.validate_persisted_inventory()

      invalid_utf8_keys = [<<255>>]

      assert {:error, :invalid_snapshot_cleanup_inventory} =
               intent
               |> Map.put(:storage_keys, invalid_utf8_keys)
               |> Map.put(:remaining_storage_keys, invalid_utf8_keys)
               |> Map.put(:object_count, 1)
               |> Map.put(:inventory_digest, inventory_digest(invalid_utf8_keys))
               |> SnapshotCleanupIntent.validate_persisted_inventory()

      completed = %{
        intent
        | status: "completed",
          remaining_storage_keys: [],
          completed_delete_passes: intent.required_delete_passes
      }

      assert :ok = SnapshotCleanupIntent.validate_persisted_inventory(completed)
    end
  end

  defp valid_attrs do
    ready_prefix = "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp"
    staging_prefix = "projects/1/snapshots/object-sets/v1/staging/AbCdEfGhIjKlMnOp"
    relative_paths = ["manifest.json", "project.json", "blobs/#{String.duplicate("a", 64)}.bin"]

    storage_keys =
      Enum.flat_map([ready_prefix, staging_prefix], fn prefix ->
        Enum.map(relative_paths, &"#{prefix}/#{&1}")
      end)

    %{
      project_snapshot_id: 1,
      cleanup_request_id: 1,
      workspace_id_snapshot: 1,
      project_id_snapshot: 1,
      project_snapshot_id_snapshot: 1,
      deletion_generation: 1,
      mode: "full",
      origin: "user",
      reason: "user_delete",
      authority_kind: "user",
      authority_actor_id: 1,
      ready_prefix: ready_prefix,
      staging_prefix: staging_prefix,
      storage_keys: storage_keys,
      inventory_digest: inventory_digest(storage_keys),
      object_count: length(storage_keys),
      estimated_cleanup_bytes: 1,
      status: "pending",
      retry_count: 0,
      provider_namespace_fingerprint: String.duplicate("f", 64),
      requested_at: ~U[2026-08-05 00:00:00Z]
    }
  end

  defp rebuild_keys_and_digest(attrs) do
    storage_keys =
      Enum.map(attrs.storage_keys, fn key ->
        key
        |> String.replace(valid_attrs().ready_prefix, attrs.ready_prefix)
        |> String.replace(valid_attrs().staging_prefix, attrs.staging_prefix)
      end)

    attrs
    |> Map.put(:storage_keys, storage_keys)
    |> Map.put(:inventory_digest, inventory_digest(storage_keys))
  end

  defp persisted_intent(attrs) do
    attrs =
      attrs
      |> Map.put(:remaining_storage_keys, attrs.storage_keys)
      |> Map.put(:required_delete_passes, 1)
      |> Map.put(:completed_delete_passes, 0)

    struct!(SnapshotCleanupIntent, attrs)
  end

  defp inventory_digest(keys) do
    keys
    |> Enum.sort()
    |> Enum.map_join(fn key -> "#{byte_size(key)}:#{key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
