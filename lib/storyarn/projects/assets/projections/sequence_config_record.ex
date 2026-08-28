defmodule Storyarn.Projects.Assets.Persistence.SequenceConfigRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "flow_node_sequence_configs" do
    field :flow_node_id, :id, primary_key: true
    field :name, :string
  end
end
