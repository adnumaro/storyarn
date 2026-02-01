defmodule Storyarn.Accounts.UserIdentity do
  @moduledoc """
  Schema for storing OAuth identities linked to users.

  Each user can have multiple identities (GitHub, Google, Discord).
  OAuth tokens are encrypted at rest using Cloak.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @providers ~w(github google discord)

  @type t :: %__MODULE__{
          id: integer() | nil,
          provider: String.t() | nil,
          provider_id: String.t() | nil,
          provider_email: String.t() | nil,
          provider_name: String.t() | nil,
          provider_avatar: String.t() | nil,
          provider_meta: map() | nil,
          provider_token_encrypted: binary() | nil,
          provider_refresh_token_encrypted: binary() | nil,
          provider_token: String.t() | nil,
          provider_refresh_token: String.t() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "user_identities" do
    field :provider, :string
    field :provider_id, :string
    field :provider_email, :string
    field :provider_name, :string
    field :provider_avatar, :string
    field :provider_meta, :map, default: %{}

    # Encrypted token storage
    field :provider_token_encrypted, Storyarn.Encrypted.Binary
    field :provider_refresh_token_encrypted, Storyarn.Encrypted.Binary

    # Virtual fields for API compatibility (input only)
    field :provider_token, :string, virtual: true, redact: true
    field :provider_refresh_token, :string, virtual: true, redact: true

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
    |> encrypt_tokens()
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

  # Encrypts virtual token fields into encrypted columns
  defp encrypt_tokens(changeset) do
    changeset
    |> maybe_encrypt_field(:provider_token, :provider_token_encrypted)
    |> maybe_encrypt_field(:provider_refresh_token, :provider_refresh_token_encrypted)
  end

  defp maybe_encrypt_field(changeset, virtual_field, encrypted_field) do
    case get_change(changeset, virtual_field) do
      nil -> changeset
      value -> put_change(changeset, encrypted_field, value)
    end
  end

  @doc """
  Returns the decrypted provider token.
  """
  def get_provider_token(%__MODULE__{provider_token_encrypted: nil}), do: nil
  def get_provider_token(%__MODULE__{provider_token_encrypted: token}), do: token

  @doc """
  Returns the decrypted provider refresh token.
  """
  def get_provider_refresh_token(%__MODULE__{provider_refresh_token_encrypted: nil}), do: nil

  def get_provider_refresh_token(%__MODULE__{provider_refresh_token_encrypted: token}),
    do: token

  @doc """
  Returns the list of supported OAuth providers.
  """
  def providers, do: @providers
end
