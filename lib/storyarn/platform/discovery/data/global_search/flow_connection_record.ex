defmodule Storyarn.Platform.GlobalSearch.Persistence.FlowConnectionRecord do
  @moduledoc false

  use Ecto.Schema

  schema "flow_connections" do
    field :label, :string
    field :flow_id, :id
  end
end
