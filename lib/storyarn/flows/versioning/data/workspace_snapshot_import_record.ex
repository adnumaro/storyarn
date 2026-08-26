defmodule Storyarn.Flows.Versioning.Data.WorkspaceSnapshotImportRecord do
  @moduledoc """
  Versioning-owned workspace-import projection used only for storage reservation accounting.
  """

  use Ecto.Schema

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string
    field :reserved_bytes, :integer

    timestamps(type: :utc_datetime)
  end
end
