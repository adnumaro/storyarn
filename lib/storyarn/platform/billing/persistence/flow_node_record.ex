defmodule Storyarn.Platform.Billing.Persistence.FlowNodeRecord do
  @moduledoc false

  use Ecto.Schema

  schema "flow_nodes" do
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end
