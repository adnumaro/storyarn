defmodule Storyarn.AI.Routing.Data.UserRecord do
  @moduledoc "Consumer-local user identity used to bind an AI route option."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end
