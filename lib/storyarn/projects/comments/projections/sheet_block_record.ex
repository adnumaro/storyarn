defmodule Storyarn.Projects.Comments.Projections.SheetBlockRecord do
  @moduledoc false
  use Ecto.Schema

  schema "blocks" do
    field(:sheet_id, :integer)
    field(:type, :string)
    field(:config, :map)
    field(:variable_name, :string)
    field(:column_group_id, Ecto.UUID)
    field(:deleted_at, :utc_datetime)
    field(:inserted_at, :utc_datetime)
  end
end
