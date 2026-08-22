defmodule Storyarn.References.Persistence.FlowNodeRecord do
  @moduledoc """
  References-owned projection and repair model for `flow_nodes`.

  It intentionally contains only the columns needed to extract and maintain
  entity and variable references. Flow editor associations and editor-specific
  changesets remain private to the Flow bounded context.
  """

  use Ecto.Schema

  alias Storyarn.References.Persistence.FlowRecord

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
