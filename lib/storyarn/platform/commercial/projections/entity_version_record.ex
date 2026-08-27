defmodule Storyarn.Platform.Billing.Persistence.EntityVersionRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_versions" do
    field :entity_type, :string
    field :entity_id, :id
    field :title, :string
    field :is_auto, :boolean, default: false
    field :project_id, :id

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
