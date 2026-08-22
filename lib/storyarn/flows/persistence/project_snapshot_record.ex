defmodule Storyarn.Flows.Persistence.ProjectSnapshotRecord do
  @moduledoc false

  use Ecto.Schema

  schema "project_snapshots" do
    field :project_id, :id
    field :mode, :string
    field :lifecycle_state, :string
    field :accounted_size_bytes, :integer
    field :accounting_version, :integer

    timestamps(updated_at: false, type: :utc_datetime)
  end
end
