defmodule Storyarn.Scenes.SceneAmbientFlow do
  @moduledoc """
  Schema for linking flows to scenes as ambient (auto-playing) background flows.

  An ambient flow runs automatically based on its trigger type:
  - `on_enter` — fires when the scene loads
  - `timed` — fires periodically (interval_ms in trigger_config)
  - `on_event` — fires when a variable changes (variable_ref in trigger_config)
  - `one_shot` — fires once per session, then skipped
  """
  use Ecto.Schema
  use Gettext, backend: Storyarn.Gettext
  import Ecto.Changeset

  alias Storyarn.Flows.Flow
  alias Storyarn.Scenes.Scene

  @type t :: %__MODULE__{
          id: integer() | nil,
          trigger_type: String.t(),
          trigger_config: map(),
          priority: integer(),
          enabled: boolean(),
          position: integer(),
          scene_id: integer() | nil,
          scene: Scene.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @trigger_types ~w(on_enter timed on_event one_shot)

  def trigger_types, do: @trigger_types

  schema "scene_ambient_flows" do
    field :trigger_type, :string, default: "on_enter"
    field :trigger_config, :map, default: %{}
    field :priority, :integer, default: 0
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :scene, Scene
    belongs_to :flow, Flow

    timestamps(type: :utc_datetime)
  end

  def changeset(ambient_flow, attrs) do
    ambient_flow
    |> cast(attrs, [:flow_id, :trigger_type, :trigger_config, :priority, :enabled, :position])
    |> validate_required([:flow_id])
    |> validate_inclusion(:trigger_type, @trigger_types)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> sanitize_trigger_config()
    |> validate_trigger_config()
    |> foreign_key_constraint(:scene_id)
    |> foreign_key_constraint(:flow_id)
    |> unique_constraint([:scene_id, :flow_id],
      name: :scene_ambient_flows_scene_id_flow_id_index,
      message: dgettext("scenes", "this flow is already linked to this scene")
    )
  end

  defp sanitize_trigger_config(changeset) do
    case {get_field(changeset, :trigger_type), get_field(changeset, :trigger_config)} do
      {"timed", config} when is_map(config) ->
        put_change(changeset, :trigger_config, Map.take(config, ["interval_ms"]))

      {"on_event", config} when is_map(config) ->
        put_change(changeset, :trigger_config, Map.take(config, ["variable_ref"]))

      _ ->
        put_change(changeset, :trigger_config, %{})
    end
  end

  defp validate_trigger_config(changeset) do
    case get_field(changeset, :trigger_type) do
      "timed" -> validate_timed_config(changeset)
      "on_event" -> validate_on_event_config(changeset)
      _ -> changeset
    end
  end

  defp validate_timed_config(changeset) do
    interval = (get_field(changeset, :trigger_config) || %{})["interval_ms"]

    if is_integer(interval) and interval >= 1_000 do
      changeset
    else
      add_error(
        changeset,
        :trigger_config,
        dgettext("scenes", "timed trigger requires interval_ms >= 1000")
      )
    end
  end

  defp validate_on_event_config(changeset) do
    # Allow empty variable_ref — user picks the trigger type first, then the variable
    changeset
  end
end
