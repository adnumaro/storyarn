defmodule Storyarn.Projects.References.Persistence.ScenePinRecord do
  @moduledoc "References-owned read model for Scene pin variable sources."

  use Ecto.Schema

  alias Storyarn.Projects.References.Persistence.SceneRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          scene_id: integer() | nil,
          label: String.t() | nil,
          condition: map() | nil
        }

  schema "scene_pins" do
    field :label, :string
    field :condition, :map

    belongs_to :scene, SceneRecord

    timestamps(type: :utc_datetime)
  end
end
