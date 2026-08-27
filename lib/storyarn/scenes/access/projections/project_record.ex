defmodule Storyarn.Scenes.Access.Projections.ProjectRecord do
  @moduledoc "Access-owned consumer-local SQL projection used to authorize Scene project reads without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Access.Projections.WorkspaceRecord

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
