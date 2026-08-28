defmodule Storyarn.Platform.Notifications.Projections.UserRecord do
  @moduledoc """
  Notification-owned projection of the user identity and presentation fields.

  It maps the shared `users` table without importing the Accounts aggregate.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
    field :is_super_admin, :boolean, default: false
    field :locale, :string

    timestamps(type: :utc_datetime)
  end
end
