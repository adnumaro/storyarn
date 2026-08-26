defmodule Storyarn.AI.Operations.Data.UserRecord do
  @moduledoc "Consumer-local actor identity referenced by durable AI operations and results."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end
