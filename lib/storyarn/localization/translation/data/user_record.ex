defmodule Storyarn.Localization.Translation.Data.UserRecord do
  @moduledoc """
  Translation-owned read projection over the requester identity needed by
  translation-run completion notifications.

  It is passive association data and performs no persistence I/O.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{id: integer() | nil}

  schema "users" do
  end
end
