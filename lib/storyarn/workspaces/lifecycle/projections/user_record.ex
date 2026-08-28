defmodule Storyarn.Workspaces.Lifecycle.Projections.UserRecord do
  @moduledoc """
  Consumer-local SQL projection of the user fields Workspace lifecycle needs.

  Accounts owns user behavior and writes. Lifecycle uses this passive record
  for ownership associations and creation locking without importing Accounts'
  code model.
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
