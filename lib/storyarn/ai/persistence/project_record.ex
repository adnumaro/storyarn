defmodule Storyarn.AI.Persistence.ProjectRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
