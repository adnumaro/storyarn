defmodule Storyarn.Platform.Billing.Persistence.WorkspaceSnapshotImportRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  # Persisted cross-context contract: Projects writes these lifecycle values;
  # Billing counts the same in-flight set for both capacity and import slots.
  # The parity test fails if either context changes the shared vocabulary alone.
  @active_statuses ~w(uploading queued running retrying)

  schema "workspace_snapshot_imports" do
    field :workspace_id, :id
    field :status, :string
    field :reserved_bytes, :integer

    timestamps(type: :utc_datetime)
  end

  @doc "Returns persisted import states that continue to own capacity and an import slot."
  @spec active_statuses() :: [String.t()]
  def active_statuses, do: @active_statuses
end
