defmodule Storyarn.Projects.Assets.Persistence.SequenceTrackRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_node_sequence_tracks" do
    field :flow_node_id, :id
    field :asset_id, :id
    field :track_key, :string
    field :is_override, :boolean, default: false
    field :overridden_fields, {:array, :string}, default: []
    field :removed, :boolean, default: false
    field :kind, :string
  end
end
