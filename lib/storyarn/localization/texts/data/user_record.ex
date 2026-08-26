defmodule Storyarn.Localization.Texts.Data.UserRecord do
  @moduledoc """
  Consumer-local Account identity projection for translator and reviewer links.

  It is passive association data with no persistence behavior. Accounts keeps
  ownership of user lifecycle and ordinary writes.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "users" do
    timestamps(type: :utc_datetime)
  end
end
