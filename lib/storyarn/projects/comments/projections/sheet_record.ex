defmodule Storyarn.Projects.Comments.Projections.SheetRecord do
  @moduledoc false
  use Ecto.Schema

  schema "sheets" do
    field :project_id, :integer
    field :name, :string
    field :deleted_at, :utc_datetime
    field :inserted_at, :utc_datetime
  end
end
