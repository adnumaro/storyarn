defmodule Storyarn.Scenes.Persistence.FlowConnectionRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_connections" do
    field :source_pin, :string
    field :target_pin, :string
    field :label, :string
    field :flow_id, :id
    field :source_node_id, :id
    field :target_node_id, :id

    timestamps(type: :utc_datetime)
  end
end
