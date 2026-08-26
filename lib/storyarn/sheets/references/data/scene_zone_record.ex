defmodule Storyarn.Sheets.References.Data.SceneZoneRecord do
  @moduledoc """
  References-local projection of Scene zone targets and variable-bearing data.

  It contains the foreign facts needed for backlinks and staleness reporting,
  without importing Scene editor behavior.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_zones" do
    field :name, :string
    field :action_data, :map, default: %{}
    field :action_type, :string
    field :condition, :map
    field :target_type, :string
    field :target_id, :integer
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
