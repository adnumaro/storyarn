defmodule Storyarn.Projects.Assets.Persistence.SequenceVisualLayerRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_node_sequence_visual_layers" do
    field :flow_node_id, :id
    field :asset_id, :id
    field :layer_key, :string
    field :overridden_fields, {:array, :string}, default: []
    field :removed, :boolean, default: false
    field :kind, :string
    field :label, :string
    field :z_index, :integer, default: 0
  end
end
