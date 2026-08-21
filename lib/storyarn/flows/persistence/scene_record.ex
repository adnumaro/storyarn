defmodule Storyarn.Flows.Persistence.SceneRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scenes" do
    field :name, :string
    field :shortcut, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime
    field :updated_at, :utc_datetime
  end
end
