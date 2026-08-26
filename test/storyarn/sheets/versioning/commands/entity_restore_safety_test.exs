defmodule Storyarn.Sheets.Versioning.Commands.EntityRestoreSafetyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Versioning.Commands.EntityRestoreSafety
  alias Storyarn.Sheets.Versioning.EntityVersionRecord, as: EntityVersion

  defmodule FakeRepo do
    def one(_query), do: Process.get({__MODULE__, :version})
  end

  describe "lock_pre_restore_version/5" do
    test "keeps the trusted internal boundary optional" do
      assert {:ok, :not_required} =
               EntityRestoreSafety.lock_pre_restore_version(
                 FakeRepo,
                 "sheet",
                 entity(),
                 33,
                 []
               )
    end

    test "rejects invalid identity metadata before querying the durable row" do
      Process.put({FakeRepo, :version}, version())

      assert {:error, :invalid_pre_restore_version_identity} =
               EntityRestoreSafety.lock_pre_restore_version(
                 FakeRepo,
                 "sheet",
                 entity(),
                 33,
                 pre_restore_version_identity: %{identity(version()) | checksum: nil}
               )
    end

    test "fails closed when the durable row is missing" do
      Process.put({FakeRepo, :version}, nil)

      assert {:error, :pre_restore_version_not_durable} =
               EntityRestoreSafety.lock_pre_restore_version(
                 FakeRepo,
                 "sheet",
                 entity(),
                 33,
                 pre_restore_version_identity: identity(version())
               )
    end

    test "fails closed when the locked row no longer has the supplied identity" do
      Process.put({FakeRepo, :version}, version(checksum: String.duplicate("b", 64)))

      assert {:error, :pre_restore_version_identity_mismatch} =
               EntityRestoreSafety.lock_pre_restore_version(
                 FakeRepo,
                 "sheet",
                 entity(),
                 33,
                 pre_restore_version_identity: identity(version())
               )
    end

    test "returns the locked row when its identity remains exact" do
      version = version()
      Process.put({FakeRepo, :version}, version)

      assert {:ok, ^version} =
               EntityRestoreSafety.lock_pre_restore_version(
                 FakeRepo,
                 "sheet",
                 entity(),
                 33,
                 pre_restore_version_identity: identity(version)
               )
    end
  end

  describe "verify_pre_restore_baseline/5" do
    test "checks only matching entity-version restore actions" do
      assert :ok =
               EntityRestoreSafety.verify_pre_restore_baseline(
                 "sheet",
                 entity(),
                 [
                   restore_action: {:project_snapshot_restore, "full"},
                   pre_restore_snapshot: :invalid
                 ],
                 fn _entity -> raise ArgumentError, "must not run" end,
                 :sheet_changed_since_pre_restore_snapshot
               )
    end

    test "rejects an explicitly invalid pre-restore snapshot" do
      assert {:error, :invalid_pre_restore_snapshot} =
               EntityRestoreSafety.verify_pre_restore_baseline(
                 "sheet",
                 entity(),
                 [restore_action: {:entity_version_restore, "sheet"}, pre_restore_snapshot: []],
                 fn _entity -> raise ArgumentError, "must not run" end,
                 :sheet_changed_since_pre_restore_snapshot
               )
    end

    test "compares the locked snapshot and preserves the builder-specific error" do
      assert {:error, :sheet_changed_since_pre_restore_snapshot} =
               EntityRestoreSafety.verify_pre_restore_baseline(
                 "sheet",
                 entity(),
                 [
                   restore_action: {:entity_version_restore, "sheet"},
                   pre_restore_snapshot: %{"name" => "before"}
                 ],
                 fn _entity -> %{"name" => "after"} end,
                 :sheet_changed_since_pre_restore_snapshot
               )
    end

    test "normalizes every builder snapshot through its persisted JSON representation" do
      assert :ok =
               EntityRestoreSafety.verify_pre_restore_baseline(
                 "sheet",
                 entity(),
                 [
                   restore_action: {:entity_version_restore, "sheet"},
                   pre_restore_snapshot: %{"name" => "same", "weight" => "1.50"}
                 ],
                 fn _entity -> %{name: "same", weight: Decimal.new("1.50")} end,
                 :sheet_changed_since_pre_restore_snapshot
               )
    end

    test "preserves validation failures from snapshot construction" do
      assert {:error, {:pre_restore_snapshot_validation_failed, "invalid child"}} =
               EntityRestoreSafety.verify_pre_restore_baseline(
                 "sheet",
                 entity(),
                 [
                   restore_action: {:entity_version_restore, "sheet"},
                   pre_restore_snapshot: %{}
                 ],
                 fn _entity -> raise ArgumentError, "invalid child" end,
                 :sheet_changed_since_pre_restore_snapshot
               )
    end
  end

  defp entity, do: %{id: 11, project_id: 22}

  defp version(attrs \\ []) do
    struct!(
      EntityVersion,
      Keyword.merge(
        [
          id: 44,
          entity_type: "sheet",
          entity_id: 11,
          project_id: 22,
          created_by_id: 33,
          version_number: 2,
          storage_key: "entity-versions/sheet/11/2.json.gz",
          snapshot_size_bytes: 123,
          checksum: String.duplicate("a", 64)
        ],
        attrs
      )
    )
  end

  defp identity(version) do
    Map.take(version, [
      :id,
      :entity_type,
      :entity_id,
      :project_id,
      :created_by_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes,
      :checksum
    ])
  end
end
