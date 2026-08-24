defmodule Storyarn.Platform.Billing.Persistence.FlowRecord do
  @moduledoc false

  use Ecto.Schema

  schema "flows" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end
