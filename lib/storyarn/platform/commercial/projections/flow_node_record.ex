defmodule Storyarn.Platform.Billing.Persistence.FlowNodeRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "flow_nodes" do
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end
