defmodule Storyarn.Commercial.Billing.Persistence.FlowRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  schema "flows" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end
