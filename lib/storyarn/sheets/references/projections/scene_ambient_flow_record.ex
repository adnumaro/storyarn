defmodule Storyarn.Sheets.References.Projections.SceneAmbientFlowRecord do
  @moduledoc """
  References-local projection of ambient Flow bindings authored in Scenes.

  Sheets reads the trigger payload and foreign identities only to maintain and
  explain variable-reference projections.
  """

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
