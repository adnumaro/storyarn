defmodule Storyarn.References.Persistence.FlowRecord do
  @moduledoc """
  References-owned read model for the `flows` table.

  References consumes only the identity, project scope, display name and
  lifecycle state needed to resolve cross-entity projections. Keeping this
  schema local prevents projection maintenance from depending on the Flow
  editor's persistence model.
  """

  use Ecto.Schema

  alias Storyarn.References.Persistence.FlowNodeRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          project_id: integer() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    has_many :nodes, FlowNodeRecord, foreign_key: :flow_id

    timestamps(type: :utc_datetime)
  end
end
