defmodule Storyarn.Scenes.Assets.Data.WorkspaceRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Scene asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end
end
