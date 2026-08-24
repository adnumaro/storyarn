defmodule Storyarn.Projects.References.Persistence.SheetAvatarRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :sheet_id, :id
    field :asset_id, :id

    timestamps(type: :utc_datetime)
  end
end
