defmodule Storyarn.Sheets.Versioning.Projections.FlowRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Sheet versions without importing another context's schema."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :is_main, :boolean, default: false
    field :settings, :map, default: %{}
    field :project_id, :id
    field :scene_id, :id
    field :current_version_id, :id
    field :deleted_at, :utc_datetime
    field :parent_id, :id

    timestamps(type: :utc_datetime)
  end
end
