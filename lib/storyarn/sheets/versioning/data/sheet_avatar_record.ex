defmodule Storyarn.Sheets.Versioning.Data.SheetAvatarRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to validate Sheet-owned avatar references without importing another capability's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :sheet_id, :id
    field :asset_id, :id

    timestamps(type: :utc_datetime)
  end
end
