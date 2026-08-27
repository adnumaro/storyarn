defmodule Storyarn.Sheets.Versioning.Projections.UserRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Sheet versions without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
  end
end
