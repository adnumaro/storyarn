defmodule Storyarn.Scenes.Persistence.WorkspaceRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
