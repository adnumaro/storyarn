defmodule Storyarn.Scenes.Assets.Projections.ProjectRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Scene asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Assets.Projections.WorkspaceRecord

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
