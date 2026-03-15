defmodule Storyarn.Versioning.SnapshotBuilder do
  @moduledoc """
  Behaviour for entity-specific snapshot building and restoration.

  Each entity type (sheet, flow, scene) implements this behaviour to define
  how snapshots are captured, restored, and compared.
  """

  @doc """
  Builds a snapshot map from the given entity.
  The entity should have all necessary associations preloaded.
  """
  @callback build_snapshot(entity :: struct()) :: map()

  @doc """
  Restores an entity from a snapshot.
  Returns `{:ok, updated_entity}` or `{:error, reason}`.
  """
  @callback restore_snapshot(entity :: struct(), snapshot :: map(), opts :: keyword()) ::
              {:ok, struct()} | {:error, term()}

  @doc """
  Materializes a brand-new entity from a snapshot.

  Returns the created root entity together with an old-to-new ID map for any
  child entities materialized from the snapshot.
  """
  @callback instantiate_snapshot(project_id :: integer(), snapshot :: map(), opts :: keyword()) ::
              {:ok, struct(), map()} | {:error, term()}

  @type change :: %{
          category: atom(),
          action: :added | :removed | :modified,
          detail: String.t()
        }

  @doc """
  Compares two snapshots and returns a structured list of changes.

  Each change has a `:category` (entity-specific, e.g. `:node`, `:block`, `:pin`),
  an `:action` (`:added`, `:removed`, `:modified`), and a human-readable `:detail` string.

  Returns an empty list when snapshots are identical.
  """
  @callback diff_snapshots(old_snapshot :: map(), new_snapshot :: map()) :: [change()]

  @doc """
  Scans a snapshot for external references (foreign keys to other entities).
  Returns a list of reference maps with type, id, and context description.

  Each reference is: `%{type: :asset | :sheet | :flow | :scene, id: integer(), context: String.t()}`
  """
  @callback scan_references(snapshot :: map()) :: [map()]

  @optional_callbacks [scan_references: 1]
end
