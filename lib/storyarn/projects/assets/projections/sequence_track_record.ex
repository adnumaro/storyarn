defmodule Storyarn.Projects.Assets.Persistence.SequenceTrackRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_node_sequence_tracks" do
    field :flow_node_id, :id
    field :asset_id, :id
    field :kind, :string
  end
end
