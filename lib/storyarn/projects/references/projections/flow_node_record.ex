defmodule Storyarn.Projects.References.Persistence.FlowNodeRecord do
  @moduledoc """
  References-owned read projection over `flow_nodes`.

  It intentionally contains only the columns needed to inspect Flow-authored
  entity and variable references during Project-wide coordination. Flow owns
  ordinary node writes; exact Project reconstitution and lifecycle exceptions
  use their separately classified records.
  """

  use Ecto.Schema

  alias Storyarn.Projects.References.Persistence.FlowRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          data: map(),
          word_count: integer(),
          derivatives_fingerprint: String.t() | nil,
          deleted_at: DateTime.t() | nil,
          flow_id: integer() | nil,
          parent_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_nodes" do
    field :type, :string
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :data, :map, default: %{}
    field :word_count, :integer, default: 0
    field :derivatives_fingerprint, :string
    field :deleted_at, :utc_datetime

    belongs_to :flow, FlowRecord
    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end
end
