defmodule Storyarn.Platform.Onboarding.Persistence.UserRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

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
