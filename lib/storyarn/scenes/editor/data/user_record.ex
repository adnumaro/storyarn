defmodule Storyarn.Scenes.Editor.Data.UserRecord do
  @moduledoc "Editor-owned consumer-local SQL projection used by Scene editing without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
  end
end
