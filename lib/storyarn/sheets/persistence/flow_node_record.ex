defmodule Storyarn.Sheets.Persistence.FlowNodeRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_nodes" do
    field :type, :string
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :data, :map, default: %{}
    field :word_count, :integer, default: 0
    field :derivatives_fingerprint, :string
    field :deleted_at, :utc_datetime
    field :flow_id, :id
    field :parent_id, :id

    timestamps(type: :utc_datetime)
  end
end
