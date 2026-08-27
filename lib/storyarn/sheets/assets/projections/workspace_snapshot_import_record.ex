defmodule Storyarn.Sheets.Assets.Projections.WorkspaceSnapshotImportRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Sheet asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string
    field :reserved_bytes, :integer
    field :materialization_storage_keys, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end
end
