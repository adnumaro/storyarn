defmodule Storyarn.Projects.Persistence.SceneAmbientFlowRecord do
  @moduledoc false

  use Ecto.Schema
  use Gettext, backend: Storyarn.Gettext

  import Ecto.Changeset

  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SceneRecord

  @trigger_types ~w(on_enter timed on_event one_shot)

  schema "scene_ambient_flows" do
    field :trigger_type, :string, default: "on_enter"
    field :trigger_config, :map, default: %{}
    field :priority, :integer, default: 0
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :scene, SceneRecord
    belongs_to :flow, FlowRecord

    timestamps(type: :utc_datetime)
  end

  def trigger_types, do: @trigger_types

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
      "timed" ->
        interval = (get_field(changeset, :trigger_config) || %{})["interval_ms"]

        if is_integer(interval) and interval >= 1_000,
          do: changeset,
          else: add_error(changeset, :trigger_config, dgettext("scenes", "timed trigger requires interval_ms >= 1000"))

      _ ->
        changeset
    end
  end
end
