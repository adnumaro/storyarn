defmodule Storyarn.Sheets.Persistence.WorkspaceSnapshotImportRecord do
  @moduledoc false

  use Ecto.Schema

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string
    field :reserved_bytes, :integer
    field :materialization_storage_keys, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end
end
