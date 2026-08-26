defmodule Storyarn.Sheets.References.Data.FlowRecord do
  @moduledoc """
  References-local projection of Flow identity, project ownership, and trash.

  Sheets reads this shape to validate targets and label backlinks; it does not
  import the Flow aggregate or own Flow lifecycle.
  """

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
