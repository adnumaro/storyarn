defmodule Storyarn.Workspaces.Invitations.Data.UserRecord do
  @moduledoc """
  Consumer-local SQL projection of the user fields Invitations needs.

  Accounts remains the semantic owner of users. This passive record exists so
  Invitations can preload invitation recipients and inviters without importing
  the Accounts code model.
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
