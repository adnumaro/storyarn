defmodule Storyarn.Accounts.UserIdentity do
  @moduledoc """
  Schema for storing OAuth identities linked to users.

  Each user can have multiple identities (GitHub, Google, Discord).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @providers ~w(github google discord)

  schema "user_identities" do
    field :provider, :string
    field :provider_id, :string
    field :provider_email, :string
    field :provider_name, :string
    field :provider_avatar, :string
    field :provider_token, :string, redact: true
    field :provider_refresh_token, :string, redact: true
    field :provider_meta, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :provider,
      :provider_id,
      :provider_email,
      :provider_name,
      :provider_avatar,
      :provider_token,
      :provider_refresh_token,
      :provider_meta,
      :user_id
    ])
    |> validate_required([:provider, :provider_id, :user_id])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint([:provider, :provider_id],
      name: :user_identities_provider_provider_id_index,
      message: "already linked to another account"
    )
    |> unique_constraint([:user_id, :provider],
      name: :user_identities_user_id_provider_index,
      message: "already linked"
    )
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of supported OAuth providers.
  """
  def providers, do: @providers
end
