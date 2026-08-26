defmodule Storyarn.AI.ManagedSpend.Data.UserRecord do
  @moduledoc "Read model for the actor identity retained on managed allowance grants."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end
