defmodule Storyarn.Platform.Billing.Persistence.ProjectRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :owner_id, :id
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :id

    timestamps(type: :utc_datetime)
  end
end
