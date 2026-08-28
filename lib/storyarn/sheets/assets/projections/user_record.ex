defmodule Storyarn.Sheets.Assets.Projections.UserRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Sheet asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
  end
end
