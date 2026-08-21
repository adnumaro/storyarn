defmodule Storyarn.Versioning.ProjectSnapshotArchiveReader.Plan do
  @moduledoc false

  alias Storyarn.Versioning.ProjectSnapshotArchiveReader.Entry

  @enforce_keys [
    :manifest,
    :project,
    :manifest_json,
    :archive_key,
    :archive_size_bytes,
    :archive_checksum,
    :archive_identity,
    :entries_by_path,
    :entry_order
  ]
  defstruct [
    :manifest,
    :project,
    :manifest_json,
    :archive_key,
    :archive_size_bytes,
    :archive_checksum,
    :archive_identity,
    :logical_asset_bytes,
    :entries_by_path,
    :entry_order
  ]

  @type archive_identity :: {:etag, String.t()} | {:sha256, String.t()}

  @type t :: %__MODULE__{
          manifest: map(),
          project: map(),
          manifest_json: binary(),
          archive_key: String.t(),
          archive_size_bytes: pos_integer(),
          archive_checksum: String.t(),
          archive_identity: archive_identity(),
          logical_asset_bytes: non_neg_integer() | nil,
          entries_by_path: %{String.t() => Entry.t()},
          entry_order: [String.t()]
        }
end
