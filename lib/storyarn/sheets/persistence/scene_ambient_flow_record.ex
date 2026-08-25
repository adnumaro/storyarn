defmodule Storyarn.Sheets.Persistence.SceneAmbientFlowRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_ambient_flows" do
    field :trigger_type, :string
    field :trigger_config, :map, default: %{}
    field :scene_id, :id
    field :flow_id, :id

    timestamps(type: :utc_datetime)
  end
end
