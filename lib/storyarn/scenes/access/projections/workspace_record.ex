defmodule Storyarn.Scenes.Access.Projections.WorkspaceRecord do
  @moduledoc "Access-owned consumer-local SQL projection used to authorize Scene project reads without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
