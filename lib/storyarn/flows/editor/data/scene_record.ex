defmodule Storyarn.Flows.Editor.Data.SceneRecord do
  @moduledoc """
  Consumer-local Scene projection used by Flow scene and exit-target pickers.

  It is a read model over the shared table and does not expose Scene editor
  behavior inside Flows.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :shortcut, :string
    field :position, :integer, default: 0
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
