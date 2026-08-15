defmodule Storyarn.Billing.StorageReservationCleanupKeysTest do
  use ExUnit.Case, async: true

  alias Storyarn.Billing.StorageReservation

  test "canonicalizes and verifies the exact restore cleanup inventory" do
    keys = ["projects/1/z", "projects/1/a"]

    changeset =
      StorageReservation.storage_started_changeset(
        reservation("restore_staging"),
        DateTime.utc_now(),
        digest(keys),
        2,
        keys
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :cleanup_storage_keys) == Enum.sort(keys)
  end

  test "rejects absent, duplicate, count-mismatched, digest-mismatched, and oversized inventories" do
    now = DateTime.utc_now()
    valid_key = "projects/1/a"

    invalid_inputs = [
      {nil, digest([valid_key]), 1},
      {[], digest([]), 0},
      {[valid_key, valid_key], digest([valid_key, valid_key]), 2},
      {[valid_key], digest([valid_key]), 2},
      {[valid_key], String.duplicate("a", 64), 1},
      {Enum.map(1..30_001, &"projects/1/#{&1}"), String.duplicate("a", 64), 30_001}
    ]

    for {keys, inventory_digest, count} <- invalid_inputs do
      changeset =
        StorageReservation.storage_started_changeset(
          reservation("restore_staging"),
          now,
          inventory_digest,
          count,
          keys
        )

      refute changeset.valid?
      assert {_message, _metadata} = Keyword.fetch!(changeset.errors, :cleanup_storage_keys)
    end
  end

  test "accepts the canonical maximum restore inventory" do
    keys = Enum.map(1..30_000, &"projects/1/#{&1}")

    changeset =
      StorageReservation.storage_started_changeset(
        reservation("restore_staging"),
        DateTime.utc_now(),
        digest(keys),
        length(keys),
        keys
      )

    assert changeset.valid?
    assert length(Ecto.Changeset.get_change(changeset, :cleanup_storage_keys)) == 30_000
  end

  test "rejects cleanup key inventories for non-restore reservations" do
    key = "projects/1/a"

    changeset =
      StorageReservation.storage_started_changeset(
        reservation("snapshot_build"),
        DateTime.utc_now(),
        digest([key]),
        1,
        [key]
      )

    refute changeset.valid?
    assert {_message, _metadata} = Keyword.fetch!(changeset.errors, :cleanup_storage_keys)
  end

  defp reservation(kind) do
    %StorageReservation{
      kind: kind,
      status: "active",
      reserved_bytes: 100,
      generation: 1,
      accounting_version: 1
    }
  end

  defp digest(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
