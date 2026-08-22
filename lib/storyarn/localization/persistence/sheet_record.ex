defmodule Storyarn.Localization.Persistence.SheetRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "sheets" do
    field :project_id, :id
    field :name, :string
    field :shortcut, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
