defmodule Storyarn.Projects.Persistence.SequenceVisualLayerRecord do
  @moduledoc """
  A visual layer attached to a sequence flow node.

  Layers compose the Flow Player stage from the active sequence chain.
  Parent sequence layers render first; child sequence layers render above
  them. Geometry is normalized to the player stage so the same data can
  scale across viewports and later feed a 2D runtime.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Persistence.FlowNodeRecord

  @kinds ~w(backdrop character prop overlay)
  @slots [
    "full",
    "left",
    "center",
    "right",
    "custom",
    "top-left",
    "top-center",
    "top-right",
    "middle-left",
    "middle-center",
    "middle-right",
    "bottom-left",
    "bottom-center",
    "bottom-right"
  ]
  @fits ~w(cover contain fill)
  @property_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)

  @type t :: %__MODULE__{
          id: integer() | nil,
          flow_node_id: integer() | nil,
          flow_node: FlowNodeRecord.t() | NotLoaded.t() | nil,
          asset_id: integer() | nil,
          asset: Asset.t() | NotLoaded.t() | nil,
          layer_key: String.t() | nil,
          overridden_fields: [String.t()],
          removed: boolean(),
          kind: String.t() | nil,
          label: String.t() | nil,
          z_index: integer(),
          slot: String.t(),
          x: float(),
          y: float(),
          width: float(),
          height: float(),
          anchor_x: float(),
          anchor_y: float(),
          fit: String.t(),
          opacity: float(),
          visible: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_node_sequence_visual_layers" do
    belongs_to :flow_node, FlowNodeRecord
    belongs_to :asset, Asset, where: [deleted_at: nil]

    field :layer_key, :string
    field :overridden_fields, {:array, :string}, default: []
    field :removed, :boolean, default: false
    field :kind, :string
    field :label, :string
    field :z_index, :integer, default: 0
    field :slot, :string, default: "custom"

    field :x, :float, default: 0.0
    field :y, :float, default: 0.0
    field :width, :float, default: 1.0
    field :height, :float, default: 1.0
    field :anchor_x, :float, default: 0.0
    field :anchor_y, :float, default: 0.0

    field :fit, :string, default: "contain"
    field :opacity, :float, default: 1.0
    field :visible, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc "Returns valid visual layer kinds."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Returns valid visual layer slots."
  @spec slots() :: [String.t()]
  def slots, do: @slots

  @doc "Returns valid visual layer fit modes."
  @spec fits() :: [String.t()]
  def fits, do: @fits

  @doc "Returns the properties that can be overridden independently."
  @spec property_fields() :: [String.t()]
  def property_fields, do: @property_fields

  def create_changeset(layer, attrs) do
    attrs =
      attrs
      |> put_new_attr(:layer_key, "layer-#{Ecto.UUID.generate()}")
      |> put_new_attr(:overridden_fields, @property_fields)

    layer
    |> cast_layer(attrs)
    |> validate_required([:flow_node_id, :asset_id, :kind, :z_index, :slot, :fit, :layer_key])
    |> validate_layer()
    |> unique_constraint([:flow_node_id, :layer_key])
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  def update_changeset(layer, attrs) do
    overridden_fields = merge_overridden_fields(layer.overridden_fields, attrs)

    layer
    |> cast(attrs, [
      :asset_id,
      :kind,
      :label,
      :z_index,
      :slot,
      :x,
      :y,
      :width,
      :height,
      :anchor_x,
      :anchor_y,
      :fit,
      :opacity,
      :visible
    ])
    |> put_change(:overridden_fields, overridden_fields)
    |> validate_layer()
    |> foreign_key_constraint(:asset_id)
  end

  @doc "Builds a complete relational row whose mask contains only local overrides."
  def override_changeset(layer, attrs) do
    layer
    |> cast_layer(attrs)
    |> validate_required([:flow_node_id, :kind, :z_index, :slot, :fit, :layer_key])
    |> validate_layer()
    |> unique_constraint([:flow_node_id, :layer_key])
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  @doc "Returns selected properties to their inherited values."
  def revert_fields_changeset(layer, fields) when is_list(fields) do
    case normalize_requested_fields(fields) do
      {:ok, normalized_fields} ->
        layer
        |> change(overridden_fields: List.wrap(layer.overridden_fields) -- normalized_fields)
        |> validate_override_fields()

      {:error, message} ->
        layer
        |> change()
        |> add_error(:overridden_fields, message)
    end
  end

  @doc "Marks or unmarks the logical layer tombstone."
  def removal_changeset(layer, removed) when is_boolean(removed), do: change(layer, removed: removed)

  defp cast_layer(layer, attrs) do
    cast(layer, attrs, [
      :flow_node_id,
      :asset_id,
      :layer_key,
      :overridden_fields,
      :removed,
      :kind,
      :label,
      :z_index,
      :slot,
      :x,
      :y,
      :width,
      :height,
      :anchor_x,
      :anchor_y,
      :fit,
      :opacity,
      :visible
    ])
  end

  defp validate_layer(changeset) do
    changeset
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:slot, @slots)
    |> validate_inclusion(:fit, @fits)
    |> validate_length(:label, max: 120)
    |> validate_normalized(:x)
    |> validate_normalized(:y)
    |> validate_normalized(:anchor_x)
    |> validate_normalized(:anchor_y)
    |> validate_number(:width, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_number(:height, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_normalized(:opacity)
    |> validate_override_fields()
  end

  defp validate_override_fields(changeset) do
    case get_field(changeset, :overridden_fields) do
      nil ->
        add_error(changeset, :overridden_fields, "must be a list of supported property names")

      _fields ->
        validate_change(changeset, :overridden_fields, fn :overridden_fields, fields ->
          normalized = normalize_fields(fields)

          cond do
            length(normalized) != length(fields) ->
              [overridden_fields: "must contain unique supported property names"]

            Enum.any?(fields, &(&1 not in @property_fields)) ->
              [overridden_fields: "contains an unsupported property"]

            true ->
              []
          end
        end)
    end
  end

  defp normalize_requested_fields(fields) do
    if Enum.all?(fields, &(is_atom(&1) or is_binary(&1))) do
      normalized = normalize_fields(fields)

      cond do
        length(normalized) != length(fields) ->
          {:error, "must contain unique supported property names"}

        Enum.any?(normalized, &(&1 not in @property_fields)) ->
          {:error, "contains an unsupported property"}

        true ->
          {:ok, normalized}
      end
    else
      {:error, "contains an unsupported property"}
    end
  end

  defp merge_overridden_fields(existing, attrs) do
    existing
    |> List.wrap()
    |> Kernel.++(property_keys(attrs))
    |> normalize_fields()
  end

  defp property_keys(attrs) do
    attrs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&(&1 in @property_fields))
  end

  defp normalize_fields(fields), do: fields |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

  defp put_new_attr(attrs, key, value) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) ->
        attrs

      Enum.any?(attrs, fn {attr_key, _value} -> is_atom(attr_key) end) ->
        Map.put(attrs, key, value)

      true ->
        Map.put(attrs, string_key, value)
    end
  end

  defp validate_normalized(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
