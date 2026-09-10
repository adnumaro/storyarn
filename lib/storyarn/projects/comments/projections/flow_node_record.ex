defmodule Storyarn.Projects.Comments.Projections.FlowNodeRecord do
  @moduledoc false
  use Ecto.Schema

  schema "flow_nodes" do
    field :flow_id, :integer
    field :type, :string
    field :data, :map
    field :position_x, :float
    field :position_y, :float
    field :deleted_at, :utc_datetime
    field :inserted_at, :utc_datetime
  end
end
