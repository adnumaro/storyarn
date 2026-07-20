defmodule Storyarn.AI.AuditEntry do
  @moduledoc """
  Append-only audit trail for AI integration lifecycle events.

  Append-only is enforced by a database trigger (UPDATE/DELETE raise; the only
  allowed update is the FK nilify fired by user deletion). `:actor_id` is an
  immutable snapshot of the acting user's id that survives account deletion,
  while `:user_id` is a real FK that gets nilified.

  `:metadata` is sanitized by `Storyarn.AI.Audit` before insert — callers
  cannot write arbitrary keys (see `Audit.log/4`).
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
          actor_id: integer() | nil,
          provider: String.t() | nil,
          action: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  schema "ai_integration_audits" do
    field :actor_id, :integer
    field :provider, :string
    field :action, :string
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Changeset for a fresh audit row."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :actor_id, :provider, :action, :metadata])
    |> validate_required([:actor_id, :provider, :action])
    |> validate_inclusion(:action, @actions)
  end

  @doc "Allowed action strings — used by `Storyarn.AI.Audit` and tests."
  def actions, do: @actions
end
