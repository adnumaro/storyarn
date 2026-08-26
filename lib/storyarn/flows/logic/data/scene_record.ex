defmodule Storyarn.Flows.Logic.Data.SceneRecord do
  @moduledoc "Logic-owned lifecycle projection for Scenes that expose variables."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
