defmodule Storyarn.Architecture.ProjectStorageReservationBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Billing.StorageCleanupInventory, as: PlatformCleanupInventory
  alias Storyarn.Platform.Billing.StorageReservation, as: PlatformStorageReservation
  alias Storyarn.Projects.Persistence.StorageReservationRecord, as: ProjectStorageReservation
  alias Storyarn.Projects.StorageCleanupInventory, as: ProjectCleanupInventory

  @projects_sources ["lib/storyarn/projects.ex" | Path.wildcard("lib/storyarn/projects/**/*.ex")]
  @raw_billing_writers ~w(
    acquire_snapshot_export_lease
    commit_project_snapshot_restore_reservation
    commit_storage_reservation
    extend_storage_reservation
    mark_storage_reservation_started
    release_storage_reservation
    renew_live_storage_reservation
    reserve_storage
    storage_reservation_object_prefixes
  )

  test "Projects does not compile against Platform Billing reservation implementations" do
    forbidden = [
      [:Storyarn, :Platform, :Billing, :StorageReservation],
      [:Storyarn, :Platform, :Billing, :StorageCleanupInventory]
    ]

    violations =
      @projects_sources
      |> Enum.flat_map(fn path ->
        ast = path |> File.read!() |> Code.string_to_quoted!(file: path, columns: true)

        {_ast, aliases} =
          Macro.prewalk(ast, [], fn
            {:__aliases__, meta, segments} = node, acc ->
              aliases =
                if segments in forbidden,
                  do: ["#{path}:#{meta[:line]}: #{Enum.join(segments, ".")}" | acc],
                  else: acc

              {node, aliases}

            node, aliases ->
              {node, aliases}
          end)

        aliases
      end)
      |> Enum.uniq()
      |> Enum.sort()

    assert violations == [], """
    Projects must use its own reservation read model and cleanup digest. Billing
    writes cross only as neutral receipts through Storyarn.Platform:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the duplicated reservation schemas keep the shared SQL contract aligned" do
    assert ProjectStorageReservation.__schema__(:source) ==
             PlatformStorageReservation.__schema__(:source)

    assert MapSet.new(ProjectStorageReservation.__schema__(:fields)) ==
             MapSet.new(PlatformStorageReservation.__schema__(:fields))

    for field <- ProjectStorageReservation.__schema__(:fields) do
      assert ProjectStorageReservation.__schema__(:type, field) ==
               PlatformStorageReservation.__schema__(:type, field),
             "storage reservation field #{inspect(field)} has drifted between contexts"
    end
  end

  test "Projects cannot bypass the neutral storage-reservation anti-corruption layer" do
    writer_pattern =
      ~r/\b(?:Billing|Storyarn\.Platform\.Billing)\.(?:#{Enum.join(@raw_billing_writers, "|")})\s*\(/

    violations =
      @projects_sources
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_number} ->
          if Regex.match?(writer_pattern, line),
            do: ["#{path}:#{line_number}: #{String.trim(line)}"],
            else: []
        end)
      end)
      |> Enum.sort()

    assert violations == [], """
    Project reservation writes must cross Storyarn.Platform as neutral receipts
    through Storyarn.Projects.PlatformStorageReservations:

    #{Enum.join(violations, "\n")}
    """
  end

  test "the duplicated cleanup digest keeps the persisted protocol aligned" do
    inventories = [
      [],
      ["projects/1/a"],
      ["projects/1/b", "projects/1/a", "projects/1/a"],
      ["projects/1/ñ", "projects/1/longer-object-key"]
    ]

    for inventory <- inventories do
      assert ProjectCleanupInventory.digest(inventory) ==
               PlatformCleanupInventory.digest(inventory)
    end
  end

  test "the Project read model exposes no ordinary write changesets" do
    source = File.read!("lib/storyarn/projects/versioning/data/storage_reservation_record.ex")

    refute source =~ "import Ecto.Changeset"
    refute source =~ ~r/\bdef\s+\w+_changeset\b/
  end
end
