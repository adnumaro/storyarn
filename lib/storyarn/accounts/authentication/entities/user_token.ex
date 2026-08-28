defmodule Storyarn.Accounts.UserToken do
  @moduledoc """
  Persisted authentication-token entity.

  Issuance and verification policies live in their owning capability roles;
  this module retains the stable Ecto identity used by associations, fixtures,
  persisted data, and LiveVue encoding.
  """

  use Ecto.Schema

  alias Storyarn.Accounts.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          token: binary() | nil,
          context: String.t() | nil,
          sent_to: String.t() | nil,
          authenticated_at: DateTime.t() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
