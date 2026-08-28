defmodule Storyarn.Projects.References.Persistence.SheetAvatarRecord do
  @moduledoc """
  References-owned consumer projection of Sheet avatar identity.

  The physical `projections/` location identifies this as a passive view over the
  shared `sheet_avatars` table. The established `Persistence` module identity
  is retained for compatibility with existing callers and associations.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :sheet_id, :id
    field :asset_id, :id

    timestamps(type: :utc_datetime)
  end
end
