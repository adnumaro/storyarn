defmodule Storyarn.Localization.Persistence.FlowNodeRecord do
  @moduledoc false

  use Ecto.Schema

  schema "flow_nodes" do
    field :type, :string
    field :data, :map, default: %{}
    field :word_count, :integer, default: 0
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end
