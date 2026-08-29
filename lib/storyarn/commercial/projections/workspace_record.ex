defmodule Storyarn.Commercial.Billing.Persistence.WorkspaceRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :owner_id, :id

    timestamps(type: :utc_datetime)
  end
end
