defmodule Storyarn.Flows.AI.Projections.ProjectRecord do
  @moduledoc "AI-context projection used to lock the active owning project."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :deleted_at, :utc_datetime
  end
end
