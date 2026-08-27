defmodule Storyarn.AI.Integrations.Projections.UserRecord do
  @moduledoc """
  Minimal Integrations-owned projection of an account identity.

  The Accounts context owns the `users` table. Integrations uses this schema
  only as the association target for its own records; business code accepts
  structural actor shapes instead of depending on `Storyarn.Accounts.User`.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime)
  end
end
