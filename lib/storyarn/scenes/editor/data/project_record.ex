defmodule Storyarn.Scenes.Editor.Data.ProjectRecord do
  @moduledoc "Editor-owned consumer-local SQL projection used by Scene editing without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Editor.Data.WorkspaceRecord

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :auto_version_scenes, :boolean, default: true
    belongs_to :workspace, WorkspaceRecord
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
