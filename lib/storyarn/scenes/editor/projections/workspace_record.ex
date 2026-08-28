defmodule Storyarn.Scenes.Editor.Projections.WorkspaceRecord do
  @moduledoc "Editor-owned consumer-local SQL projection used by Scene editing without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
