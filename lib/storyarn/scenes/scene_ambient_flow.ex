defmodule Storyarn.Scenes.SceneAmbientFlow do
  @moduledoc """
  Schema for linking flows to scenes as ambient (auto-playing) background flows.

  An ambient flow runs automatically when the player enters a scene,
  providing background narrative, atmosphere, or world-state changes.
  """
  use Ecto.Schema
  use Gettext, backend: StoryarnWeb.Gettext
  import Ecto.Changeset

  alias Storyarn.Flows.Flow
  alias Storyarn.Scenes.Scene

  @type t :: %__MODULE__{
          id: integer() | nil,
          trigger_type: String.t(),
          enabled: boolean(),
          position: integer(),
          scene_id: integer() | nil,
          scene: Scene.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @trigger_types ~w(on_enter)

  schema "scene_ambient_flows" do
    field :trigger_type, :string, default: "on_enter"
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :scene, Scene
    belongs_to :flow, Flow

    timestamps(type: :utc_datetime)
  end

  def changeset(ambient_flow, attrs) do
    ambient_flow
    |> cast(attrs, [:flow_id, :trigger_type, :enabled, :position])
    |> validate_required([:flow_id])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> foreign_key_constraint(:scene_id)
    |> foreign_key_constraint(:flow_id)
    |> unique_constraint([:scene_id, :flow_id],
      name: :scene_ambient_flows_scene_id_flow_id_index,
      message: dgettext("scenes", "this flow is already linked to this scene")
    )
  end
end
