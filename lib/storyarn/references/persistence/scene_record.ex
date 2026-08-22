defmodule Storyarn.References.Persistence.SceneRecord do
  @moduledoc "References-owned read model for Scene identity and lifecycle scope."

  use Ecto.Schema

  alias Storyarn.References.Persistence.SceneAmbientFlowRecord
  alias Storyarn.References.Persistence.ScenePinRecord
  alias Storyarn.References.Persistence.SceneZoneRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          project_id: integer() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "scenes" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    has_many :pins, ScenePinRecord, foreign_key: :scene_id
    has_many :zones, SceneZoneRecord, foreign_key: :scene_id
    has_many :ambient_flows, SceneAmbientFlowRecord, foreign_key: :scene_id

    timestamps(type: :utc_datetime)
  end
end
