defmodule Storyarn.Projects.References.Persistence.SheetRecord do
  @moduledoc "References-owned read model for active Sheet namespaces."

  use Ecto.Schema

  alias Storyarn.Projects.References.Persistence.BlockRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          project_id: integer() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    has_many :blocks, BlockRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
