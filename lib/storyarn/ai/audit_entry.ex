defmodule Storyarn.AI.AuditEntry do
  @moduledoc """
  Append-only audit trail for AI integration lifecycle events.

  Rows are inserted for every connect / disconnect / validation-failure /
  auto-revoke event. `:metadata` is a free-form JSON map — callers MUST NOT
  put any part of the API key (plaintext, ciphertext, or hash) into it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User

  @actions ~w(connected disconnected validation_failed auto_revoked)

  @type action :: :connected | :disconnected | :validation_failed | :auto_revoked

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          provider: String.t() | nil,
          action: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  schema "ai_integration_audits" do
    field :provider, :string
    field :action, :string
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Changeset for a fresh audit row."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :provider, :action, :metadata])
    |> validate_required([:provider, :action])
    |> validate_inclusion(:action, @actions)
  end

  @doc "Allowed action strings — used by `Storyarn.AI.Audit` and tests."
  def actions, do: @actions
end
