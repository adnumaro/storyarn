defmodule Storyarn.Billing.Persistence.WorkspaceSnapshotImportRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  # Mirrors the active statuses owned by the Versioning import schema; the
  # billing limit counts the same in-flight set.
  @active_statuses ~w(uploading queued running retrying)

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string

    timestamps(type: :utc_datetime)
  end

  def active_statuses, do: @active_statuses
end
