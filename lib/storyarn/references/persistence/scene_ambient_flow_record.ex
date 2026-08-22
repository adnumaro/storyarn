defmodule Storyarn.References.Persistence.SceneAmbientFlowRecord do
  @moduledoc "References-owned read model for Scene ambient-flow variable sources."

  use Ecto.Schema

  alias Storyarn.References.Persistence.FlowRecord
  alias Storyarn.References.Persistence.SceneRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          scene_id: integer() | nil,
          flow_id: integer() | nil,
          trigger_type: String.t(),
          trigger_config: map()
        }

  schema "scene_ambient_flows" do
    field :trigger_type, :string, default: "on_enter"
    field :trigger_config, :map, default: %{}

    belongs_to :scene, SceneRecord
    belongs_to :flow, FlowRecord

    timestamps(type: :utc_datetime)
  end
end
