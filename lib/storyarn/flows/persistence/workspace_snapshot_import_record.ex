defmodule Storyarn.Flows.Persistence.WorkspaceSnapshotImportRecord do
  @moduledoc false

  use Ecto.Schema

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string
    field :reserved_bytes, :integer

    timestamps(type: :utc_datetime)
  end
end
