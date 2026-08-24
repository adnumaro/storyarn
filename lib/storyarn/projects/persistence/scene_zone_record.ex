defmodule Storyarn.Projects.Persistence.SceneZoneRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Projects.SceneChangesetHelpers

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.SceneRecord

  @valid_border_styles ~w(solid dashed dotted)
  @valid_target_types ~w(flow scene)
  @valid_action_types ~w(action walkable display collection)
  @valid_label_modes ~w(none text icon both)
  @valid_label_font_families ~w(system serif mono display)
  @valid_label_font_weights ~w(400 500 600 700)
  @valid_label_font_styles ~w(normal italic)
  @valid_condition_effects ~w(hide disable)
  @valid_display_modes ~w(value label_value)

  @type t :: %__MODULE__{}

  schema "scene_zones" do
    field :name, :string
    field :vertices, {:array, :map}
    field :fill_color, :string
    field :border_color, :string
    field :border_width, :integer, default: 2
    field :border_style, :string, default: "solid"
    field :opacity, :float, default: 0.3
    field :tooltip, :string
    field :position, :integer, default: 0
    field :locked, :boolean, default: false
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :condition, :map
    field :condition_effect, :string, default: "hide"
    field :action_data, :map, default: %{"assignments" => []}
    field :action_type, :string, default: "action"
    field :target_type, :string
    field :target_id, :integer
    field :label_mode, :string, default: "text"
    field :label_font_size, :integer, default: 12
    field :label_font_family, :string, default: "system"
    field :label_font_weight, :string, default: "600"
    field :label_font_style, :string, default: "normal"
    field :is_walkable, :boolean, default: false

    belongs_to :label_icon_asset, Asset, where: [deleted_at: nil]
    belongs_to :scene, SceneRecord
    belongs_to :layer, SceneLayerRecord

    timestamps(type: :utc_datetime)
  end

  def create_changeset(zone, attrs), do: shared_changeset(zone, attrs)
  def update_changeset(zone, attrs), do: shared_changeset(zone, attrs)

  defp shared_changeset(zone, attrs) do
    zone
    |> cast(attrs, [
      :name,
      :vertices,
      :fill_color,
      :border_color,
      :border_width,
      :border_style,
      :opacity,
      :target_type,
      :target_id,
      :tooltip,
      :layer_id,
      :position,
      :locked,
      :action_type,
      :action_data,
      :label_mode,
      :label_font_size,
      :label_font_family,
      :label_font_weight,
      :label_font_style,
      :label_icon_asset_id,
      :condition,
      :condition_effect,
      :is_walkable,
      :shortcut,
      :hidden
    ])
    |> validate_required([:name, :vertices])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:border_style, @valid_border_styles)
    |> validate_inclusion(:action_type, @valid_action_types)
    |> validate_inclusion(:label_mode, @valid_label_modes)
    |> validate_inclusion(:label_font_family, @valid_label_font_families)
    |> validate_inclusion(:label_font_weight, @valid_label_font_weights)
    |> validate_inclusion(:label_font_style, @valid_label_font_styles)
    |> validate_inclusion(:condition_effect, @valid_condition_effects)
    |> validate_target_pair(@valid_target_types)
    |> validate_action_data()
    |> validate_action_target()
    |> validate_walkable_type()
    |> validate_display_label_mode()
    |> validate_number(:opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:border_width, greater_than_or_equal_to: 0)
    |> validate_number(:label_font_size, greater_than_or_equal_to: 8, less_than_or_equal_to: 64)
    |> validate_length(:fill_color, max: 20)
    |> validate_color(:fill_color)
    |> validate_length(:border_color, max: 20)
    |> validate_color(:border_color)
    |> validate_length(:tooltip, max: 500)
    |> foreign_key_constraint(:label_icon_asset_id)
    |> validate_shortcut()
    |> unique_constraint(:shortcut, name: :scene_zones_scene_id_shortcut_index)
    |> validate_vertices()
    |> foreign_key_constraint(:layer_id)
  end

  defp validate_vertices(changeset) do
    case get_field(changeset, :vertices) do
      nil ->
        changeset

      vertices when is_list(vertices) ->
        cond do
          length(vertices) < 3 ->
            add_error(changeset, :vertices, "must have at least 3 points")

          not Enum.all?(vertices, &valid_point?/1) ->
            add_error(changeset, :vertices, "all coordinates must have numeric x and y values")

          true ->
            changeset
        end

      _ ->
        add_error(changeset, :vertices, "must be a list of coordinate points")
    end
  end

  defp validate_action_data(changeset) do
    action_type = get_field(changeset, :action_type)
    action_data = get_field(changeset, :action_data) || %{}
    do_validate_action_data(changeset, action_type, action_data)
  end

  defp do_validate_action_data(changeset, "action", %{"assignments" => list}) when is_list(list), do: changeset

  defp do_validate_action_data(changeset, "action", _),
    do: add_error(changeset, :action_data, "must include \"assignments\" as a list")

  defp do_validate_action_data(changeset, "display", %{"variable_ref" => ref} = data) when is_binary(ref) do
    if Map.get(data, "display_mode", "value") in @valid_display_modes,
      do: changeset,
      else: add_error(changeset, :action_data, "display_mode must be value or label_value")
  end

  defp do_validate_action_data(changeset, "display", _),
    do: add_error(changeset, :action_data, "must include \"variable_ref\"")

  defp do_validate_action_data(changeset, "collection", %{"items" => list}) when is_list(list), do: changeset

  defp do_validate_action_data(changeset, "collection", _),
    do: add_error(changeset, :action_data, "must include \"items\" as a list")

  defp do_validate_action_data(changeset, _, _), do: changeset

  defp validate_action_target(changeset) do
    if get_field(changeset, :action_type) != "action" and
         (not is_nil(get_field(changeset, :target_type)) or not is_nil(get_field(changeset, :target_id))) do
      add_error(changeset, :target_type, "is only allowed for action zones")
    else
      changeset
    end
  end

  defp validate_walkable_type(changeset) do
    case {get_field(changeset, :action_type), get_field(changeset, :is_walkable)} do
      {"walkable", true} -> changeset
      {"walkable", _} -> add_error(changeset, :is_walkable, "must be true for walkable zones")
      {_, true} -> add_error(changeset, :is_walkable, "can only be true for walkable zones")
      _ -> changeset
    end
  end

  defp validate_display_label_mode(changeset) do
    case {get_field(changeset, :action_type), get_field(changeset, :label_mode)} do
      {"display", "none"} -> add_error(changeset, :label_mode, "cannot be none for display zones")
      _ -> changeset
    end
  end

  defp valid_point?(point) when is_map(point) do
    x = point["x"] || point[:x]
    y = point["y"] || point[:y]
    is_number(x) and is_number(y)
  end

  defp valid_point?(_), do: false
end
