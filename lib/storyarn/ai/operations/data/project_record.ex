defmodule Storyarn.AI.Operations.Data.ProjectRecord do
  @moduledoc "Consumer-local Project identity referenced by durable AI operations and results."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
