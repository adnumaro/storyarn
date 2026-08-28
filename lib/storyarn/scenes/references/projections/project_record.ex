defmodule Storyarn.Scenes.References.Projections.ProjectRecord do
  @moduledoc "References-owned consumer-local SQL projection used to validate and maintain Scene reference indexes."

  use Ecto.Schema

  alias Storyarn.Scenes.References.Projections.WorkspaceRecord

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
