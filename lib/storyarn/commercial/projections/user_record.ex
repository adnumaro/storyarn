defmodule Storyarn.Commercial.Billing.Persistence.UserRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string

    timestamps(type: :utc_datetime)
  end
end
