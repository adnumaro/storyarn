defmodule Storyarn.AI.Integration do
  @moduledoc """
  Per-user connection to an AI provider (BYOK).

  The plaintext API key is never stored — the `:api_key_encrypted` column uses
  Cloak's AES-GCM cipher. `:key_last_four` is captured at connect time so the
  UI can render `sk-...abcd` without decrypting.

  The `Inspect` implementation drops the encrypted key so accidentally logging
  a struct never leaks ciphertext or ciphertext length.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Providers

  @derive {Inspect, except: [:api_key_encrypted]}

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          provider: String.t() | nil,
          api_key_encrypted: binary() | nil,
          key_last_four: String.t() | nil,
          account_email: String.t() | nil,
          account_display_name: String.t() | nil,
          available_models: [String.t()] | nil,
          connected_at: DateTime.t() | nil,
          last_validated_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ai_integrations" do
    field :provider, :string
    field :api_key_encrypted, Storyarn.Shared.EncryptedBinary, redact: true
    field :key_last_four, :string
    field :account_email, :string
    field :account_display_name, :string
    field :available_models, {:array, :string}
    field :connected_at, :utc_datetime
    field :last_validated_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a fresh connection. The plaintext key is derived by the caller
  (validated by the provider adapter first); only the encrypted form is stored.
  """
  def connect_changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :user_id,
      :provider,
      :api_key_encrypted,
      :key_last_four,
      :account_email,
      :account_display_name,
      :available_models,
      :connected_at,
      :last_validated_at
    ])
    |> validate_required([
      :user_id,
      :provider,
      :api_key_encrypted,
      :key_last_four,
      :connected_at
    ])
    |> validate_provider()
    |> validate_length(:key_last_four, is: 4)
    |> validate_length(:account_email, max: 255)
    |> validate_length(:account_display_name, max: 255)
    |> validate_available_models()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :provider],
      name: :ai_integrations_user_provider_active_index,
      message: "already connected"
    )
  end

  @doc "Record a runtime API call. Called by `Storyarn.AI.Runtime` on success."
  def touch_usage_changeset(integration, at) do
    integration
    |> cast(%{last_used_at: at}, [:last_used_at])
    |> validate_required([:last_used_at])
  end

  defp validate_provider(changeset) do
    known = Enum.map(Providers.known_ids(), &to_string/1)
    validate_inclusion(changeset, :provider, known)
  end

  defp validate_available_models(changeset) do
    validate_change(changeset, :available_models, fn :available_models, models ->
      cond do
        not is_list(models) ->
          [available_models: "must be a list"]

        length(models) > 500 ->
          [available_models: "contains too many models"]

        Enum.all?(models, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..255)) ->
          []

        true ->
          [available_models: "contains an invalid model identifier"]
      end
    end)
  end
end
