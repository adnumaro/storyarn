defmodule Storyarn.Billing.Persistence.UserRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string

    timestamps(type: :utc_datetime)
  end
end
