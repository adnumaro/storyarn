defmodule Storyarn.Scenes.Exploration.Data.UserRecord do
  @moduledoc "Exploration-owned projection of User identity."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
  end
end
