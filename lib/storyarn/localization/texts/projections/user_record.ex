defmodule Storyarn.Localization.Texts.Projections.UserRecord do
  @moduledoc """
  Consumer-local Account identity projection for translator and reviewer links.

  It carries only the identity needed to name who last translated a string. It
  is passive association data with no persistence behavior. Accounts keeps
  ownership of user lifecycle and ordinary writes.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          display_name: String.t() | nil
        }

  schema "users" do
    field :email, :string
    field :display_name, :string
    timestamps(type: :utc_datetime)
  end
end
