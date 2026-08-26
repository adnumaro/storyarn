defmodule Storyarn.Scenes.Versioning.Data.WorkspaceRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Scene versions without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
