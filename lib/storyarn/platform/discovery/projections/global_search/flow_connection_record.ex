defmodule Storyarn.Platform.GlobalSearch.Persistence.FlowConnectionRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "flow_connections" do
    field :label, :string
    field :flow_id, :id
  end
end
