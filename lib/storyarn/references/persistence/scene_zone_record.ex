defmodule Storyarn.References.Persistence.SceneZoneRecord do
  @moduledoc "References-owned read model for Scene zone variable sources."

  use Ecto.Schema

  alias Storyarn.References.Persistence.SceneRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          scene_id: integer() | nil,
          name: String.t() | nil,
          action_type: String.t() | nil,
          action_data: map(),
          condition: map() | nil
        }

  schema "scene_zones" do
    field :name, :string
    field :action_type, :string, default: "action"
    field :action_data, :map, default: %{"assignments" => []}
    field :condition, :map

    belongs_to :scene, SceneRecord

    timestamps(type: :utc_datetime)
  end
end
