defmodule Storyarn.Workspaces.Memberships.Data.UserRecord do
  @moduledoc """
  Consumer-local SQL projection of the user fields Memberships needs.

  Accounts remains the semantic owner of users. Memberships uses this passive
  record for membership associations without importing the Accounts code model.
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
