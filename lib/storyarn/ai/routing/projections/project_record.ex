defmodule Storyarn.AI.Routing.Projections.ProjectRecord do
  @moduledoc "Consumer-local Project identity used to bind an AI route option."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
