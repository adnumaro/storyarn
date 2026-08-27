defmodule Storyarn.Platform.Billing.Persistence.ProjectSnapshotRecord do
  @moduledoc """
  Billing-owned read model for project snapshot storage ownership.

  The shared table is deliberate. Keeping this projection local prevents the
  Platform control plane from compiling against the Projects aggregate.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_snapshots" do
    field :project_id, :id
    field :created_by_id, :id
    field :format_version, :integer
    field :mode, :string
    field :lifecycle_state, :string
    field :integrity_state, :string
    field :accounted_size_bytes, :integer
    field :asset_blob_size_bytes, :integer
    field :accounting_version, :integer
    field :accounting_generation, :integer
    field :origin, :string
    field :lifecycle_generation, :integer
    field :object_prefix, :string
    field :archive_storage_key, :string
    field :archive_size_bytes, :integer
    field :manifest_storage_key, :string
    field :manifest_size_bytes, :integer
    field :manifest_checksum, :string
    field :project_size_bytes, :integer
    field :project_checksum, :string
    field :total_size_bytes, :integer
    field :object_count, :integer
    field :asset_count, :integer
    field :blob_count, :integer
    field :capture_digest, :string
    field :storage_reservation_id, :id

    timestamps(updated_at: false, type: :utc_datetime)
  end
end
