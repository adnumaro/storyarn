defmodule Storyarn.Localization.Persistence.UserRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "users" do
    timestamps(type: :utc_datetime)
  end
end
