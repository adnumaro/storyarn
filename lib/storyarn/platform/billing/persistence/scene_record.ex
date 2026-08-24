defmodule Storyarn.Platform.Billing.Persistence.SceneRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scenes" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end
