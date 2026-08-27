defmodule Storyarn.Localization.ProjectAccess.Projections.SheetRecord do
  @moduledoc """
  Access-owned projection over Sheet identity used to validate project references.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "sheets" do
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
