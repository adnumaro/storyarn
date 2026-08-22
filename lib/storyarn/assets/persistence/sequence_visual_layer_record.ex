defmodule Storyarn.Assets.Persistence.SequenceVisualLayerRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_node_sequence_visual_layers" do
    field :flow_node_id, :id
    field :asset_id, :id
    field :kind, :string
    field :label, :string
    field :z_index, :integer, default: 0
  end
end
