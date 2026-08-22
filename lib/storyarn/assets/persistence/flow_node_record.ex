defmodule Storyarn.Assets.Persistence.FlowNodeRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_nodes" do
    field :type, :string
    field :data, :map, default: %{}
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end
