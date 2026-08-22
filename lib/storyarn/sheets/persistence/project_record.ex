defmodule Storyarn.Sheets.Persistence.ProjectRecord do
  @moduledoc false

  use Ecto.Schema

  schema "projects" do
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
