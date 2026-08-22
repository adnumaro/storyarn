defmodule Storyarn.Flows.Persistence.SceneRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :shortcut, :string
    field :position, :integer, default: 0
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
